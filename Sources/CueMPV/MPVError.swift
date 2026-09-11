import CMpv

/// A negative libmpv status code, with the operation that returned it.
public struct MPVError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Int32
    public let operation: String

    public init(code: Int32, operation: String) {
        self.code = code
        self.operation = operation
    }

    public var description: String {
        "\(operation) failed: \(Self.message(for: code))"
    }

    /// libmpv's text for a status code, such as "loading failed".
    public static func message(for code: Int32) -> String {
        String(cString: mpv_error_string(code))
    }

    static func check(_ code: Int32, _ operation: @autoclosure () -> String) throws {
        if code < 0 { throw MPVError(code: code, operation: operation()) }
    }
}

/// Misuse of the handle lifecycle that would crash or deadlock libmpv.
public enum MPVLifecycleError: Error, Equatable, Sendable {
    /// `mpv_terminate_destroy` must not run while a render context is alive (render.h).
    case renderContextStillAlive
    /// One core carries at most one render context; creating a second would break the first.
    case renderContextAlreadyExists
    case notInitialized
    case alreadyDestroyed
}
