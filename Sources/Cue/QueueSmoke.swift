import CueCore
import CueQueue
import Foundation

/// `--smoke-queue`: prints what the queue database holds and exits, without opening a window, showing anything or
/// touching the network. It is how an automated check confirms the app's own wiring (database path, migrations,
/// counters) on a machine nobody is watching.
enum QueueSmoke {
    static func isRequested(in arguments: [String]) -> Bool {
        arguments.contains("--smoke-queue")
    }

    /// Prints one line per fact and exits 0, or prints the error and exits 1.
    static func run(databaseURL: URL) -> Never {
        var lines: [String] = []
        do {
            let store = QueueStore(database: try QueueDatabase.open(at: databaseURL))
            let summary = try store.summary()
            lines.append("queue: migrations = \(QueueDatabase.migrationNames.joined(separator: ","))")
            lines.append("queue: pending = \(summary.pendingCount)")
            lines.append("queue: watched = \(summary.watchedCount)")
            lines.append("queue: counter = \(QueuePresentation.counterText(for: summary))")
            lines.append("queue: passed")
        } catch {
            lines.append("queue: failed: \(String(describing: error))")
            write(lines)
            exit(1)
        }
        write(lines)
        exit(0)
    }

    private static func write(_ lines: [String]) {
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}
