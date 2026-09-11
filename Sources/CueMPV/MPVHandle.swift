import CMpv
import Foundation
import os

/// Owns one libmpv core.
///
/// Threading: libmpv's client API is thread-safe. Events are drained on a private serial queue and delivered to the
/// handler there; the handler must not block. Commands and property writes use the asynchronous API, so no call here
/// blocks on the core except `initialize`, `propertyString` (diagnostics and tests only) and `destroy`.
/// Never call this type from a render thread.
public final class MPVHandle: @unchecked Sendable {
    // @unchecked: `raw` is only used through libmpv's thread-safe client API, and mutable state lives in `state`.

    /// Receives the events of one wakeup, in order, on the handle's event queue.
    public typealias EventHandler = @Sendable ([MPVEvent]) -> Void

    private struct State: Sendable {
        var handler: EventHandler?
        var initialized = false
        var destroyed = false
        var renderContextAlive = false
    }

    let raw: OpaquePointer
    private let eventQueue = DispatchQueue(label: "cue.mpv.events")
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Keeps the handle alive while libmpv holds a pointer to it in the wakeup callback.
    private var callbackRetain: Unmanaged<MPVHandle>?

    public init() throws {
        guard let raw = mpv_create() else {
            throw MPVError(code: MPV_ERROR_NOMEM.rawValue, operation: "mpv_create")
        }
        self.raw = raw
    }

    /// Sets an option before `initialize`. Values use mpv's command-line syntax.
    public func setOption(_ name: String, _ value: String) throws {
        try MPVError.check(mpv_set_option_string(raw, name, value), "set option \(name)=\(value)")
    }

    /// Starts the core and begins delivering events to `handler` on the event queue.
    public func initialize(onEvent handler: @escaping EventHandler) throws {
        try MPVError.check(mpv_initialize(raw), "mpv_initialize")
        state.withLock {
            $0.handler = handler
            $0.initialized = true
        }
        callbackRetain = Unmanaged.passRetained(self)
        mpv_set_wakeup_callback(raw, { context in
            guard let context else { return }
            Unmanaged<MPVHandle>.fromOpaque(context).takeUnretainedValue().scheduleDrain()
        }, callbackRetain?.toOpaque())
    }

    public func requestLogMessages(minimumLevel: String) throws {
        try MPVError.check(mpv_request_log_messages(raw, minimumLevel), "request log messages \(minimumLevel)")
    }

    /// Delivers `.propertyChange` events for `name`; `id` comes back in the event.
    public func observe(_ name: String, format: MPVFormat, id: UInt64 = 0) throws {
        try MPVError.check(mpv_observe_property(raw, id, name, format.raw), "observe \(name)")
    }

    /// Queues a command without waiting; completion arrives as `.commandReply(id:error:)`.
    public func command(_ arguments: [String], replyID: UInt64 = 0) throws {
        try withCStringArray(arguments) { pointer in
            try MPVError.check(mpv_command_async(raw, replyID, pointer), "command \(arguments.first ?? "")")
        }
    }

    /// Queues a property write without waiting; completion arrives as `.setPropertyReply(id:error:)`.
    public func setProperty(_ name: String, _ value: String, replyID: UInt64 = 0) throws {
        try value.withCString { cString in
            var pointer: UnsafePointer<CChar>? = cString
            try MPVError.check(mpv_set_property_async(raw, replyID, name, MPV_FORMAT_STRING, &pointer), "set \(name)")
        }
    }

    /// Blocking read. For diagnostics and tests only: never call it from the main thread during playback or from a
    /// render thread.
    public func propertyString(_ name: String) -> String? {
        guard let value = mpv_get_property_string(raw, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    /// Frees the core. The render context, if any, must be freed first.
    public func destroy() throws {
        try eventQueue.sync {
            try state.withLock { state in
                if state.destroyed { throw MPVLifecycleError.alreadyDestroyed }
                if state.renderContextAlive { throw MPVLifecycleError.renderContextStillAlive }
                state.destroyed = true
                state.handler = nil
            }
            mpv_set_wakeup_callback(raw, nil, nil)
        }
        mpv_terminate_destroy(raw)
        callbackRetain?.release()
        callbackRetain = nil
    }

    /// Claims the core's single render context slot. Throws, without changing anything, when it is taken.
    func renderContextCreated() throws {
        try state.withLock { state in
            if !state.initialized { throw MPVLifecycleError.notInitialized }
            if state.destroyed { throw MPVLifecycleError.alreadyDestroyed }
            if state.renderContextAlive { throw MPVLifecycleError.renderContextAlreadyExists }
            state.renderContextAlive = true
        }
    }

    func renderContextFreed() {
        state.withLock { $0.renderContextAlive = false }
    }

    private func scheduleDrain() {
        eventQueue.async { self.drainEvents() }
    }

    /// Drains every queued event and delivers them as one batch, so related property changes (such as
    /// `video-params/dw` and `video-params/dh`) reach the handler together.
    private func drainEvents() {
        guard let handler = state.withLock({ $0.destroyed ? nil : $0.handler }) else { return }
        var batch: [MPVEvent] = []
        while let pointer = mpv_wait_event(raw, 0), let event = MPVEvent(pointer.pointee) {
            batch.append(event)
        }
        if !batch.isEmpty { handler(batch) }
    }
}

/// Passes a NULL-terminated `const char **` built from `strings` to `body`.
func withCStringArray<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) throws -> Result
) rethrows -> Result {
    let copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    var pointers: [UnsafePointer<CChar>?] = copies.map { $0.map { UnsafePointer($0) } } + [nil]
    return try pointers.withUnsafeMutableBufferPointer { buffer in
        try body(buffer.baseAddress!)
    }
}
