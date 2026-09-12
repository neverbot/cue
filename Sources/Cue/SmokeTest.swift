import AppKit
import CueMPV
import CuePlayer
import Foundation

/// `--smoke-test <seconds>`: plays the launch input muted for a while, prints playback diagnostics and exits with 0
/// when decoding and presentation look healthy, 1 otherwise. `--smoke-hide` minimizes the window before measuring,
/// to exercise the occluded-window path. Used by scripts and manual checks, never by default.
@MainActor
enum SmokeTest {
    static let maximumDroppedFrames = 5
    nonisolated static let diagnostics = [
        "hwdec-current", "video-codec", "width", "height", "estimated-vf-fps",
        "frame-drop-count", "decoder-frame-drop-count", "vo-delayed-frame-count", "time-pos",
    ]

    static func seconds(in arguments: [String]) -> Double? {
        guard let index = arguments.firstIndex(of: "--smoke-test"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }

    static func hidesWindow(in arguments: [String]) -> Bool {
        arguments.contains("--smoke-hide")
    }

    static func run(windowController: PlayerWindowController, playFor seconds: Double, hidden: Bool) {
        do {
            try windowController.engine.handle.setProperty("mute", "yes")
        } catch {
            finish(windowController, lines: ["smoke: could not mute: \(error)"], passed: false)
        }
        Task {
            let deadline = ContinuousClock.now + .seconds(60)
            while windowController.controller.state.phase != .ready {
                if case let .failed(reason) = windowController.controller.state.phase {
                    finish(windowController, lines: ["smoke: failed: \(reason)"], passed: false)
                }
                if ContinuousClock.now > deadline {
                    finish(windowController, lines: ["smoke: timed out waiting for playback"], passed: false)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // Startup (first frames, window refit) may drop a few frames; judge steady playback only.
            let handle = windowController.engine.handle
            if hidden { windowController.window?.miniaturize(nil) }
            try? await Task.sleep(for: .seconds(1))
            let droppedBefore = await Task.detached { Int(handle.propertyString("frame-drop-count") ?? "") ?? 0 }.value
            try? await Task.sleep(for: .seconds(seconds))

            let values = await Task.detached {
                diagnostics.map { ($0, handle.propertyString($0) ?? "-") }
            }.value
            let state = windowController.controller.state
            let decoding = state.stream?.decoding ?? .hardware
            let visible = windowController.window?.occlusionState.contains(.visible) ?? false
            let hardware = values.first { $0.0 == "hwdec-current" }?.1 ?? "-"
            let dropped = (Int(values.first { $0.0 == "frame-drop-count" }?.1 ?? "") ?? 0) - droppedBefore

            var lines = values.map { "smoke: \($0.0) = \($0.1)" }
            lines.append("smoke: decoding = \(decoding == .software ? "software" : "hardware")")
            lines.append("smoke: window visible = \(visible)")
            lines.append("smoke: frames dropped while measuring = \(dropped)")
            let decodesAsSelected = decoding == .software || !["-", "no", ""].contains(hardware)
            let passed = decodesAsSelected && dropped <= maximumDroppedFrames && state.phase == .ready
            lines.append("smoke: \(passed ? "passed" : "failed")")
            finish(windowController, lines: lines, passed: passed)
        }
    }

    private static func finish(_ windowController: PlayerWindowController, lines: [String], passed: Bool) -> Never {
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        windowController.shutdown()
        exit(passed ? 0 : 1)
    }
}
