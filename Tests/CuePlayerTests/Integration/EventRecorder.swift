import CueMPV
import Foundation
import os

/// Collects mpv event batches from the handle's event queue so tests can wait for them.
final class EventRecorder: Sendable {
    private let events = OSAllocatedUnfairLock<[MPVEvent]>(initialState: [])

    var handler: MPVHandle.EventHandler {
        { [events] batch in events.withLock { $0.append(contentsOf: batch) } }
    }

    var all: [MPVEvent] { events.withLock { $0 } }

    /// Polls until `predicate` holds or `timeout` passes; returns whether it held.
    func wait(timeout: Duration = .seconds(10), until predicate: @Sendable ([MPVEvent]) -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if events.withLock({ predicate($0) }) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return events.withLock { predicate($0) }
    }

    static func lastDouble(_ name: String, in events: [MPVEvent]) -> Double? {
        for case let .propertyChange(_, eventName, .double(value)) in events.reversed() where eventName == name {
            return value
        }
        return nil
    }
}
