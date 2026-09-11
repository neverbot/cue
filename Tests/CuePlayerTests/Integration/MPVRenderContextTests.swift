import CueMPV
import Foundation
import Testing

/// The render API with a software render context, which needs no window or GPU. Opt in with `CUE_MPV_TESTS=1`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CUE_MPV_TESTS"] == "1"))
struct MPVRenderContextTests {
    @Test func refusesToDestroyTheCoreWhileARenderContextIsAlive() throws {
        let handle = try MPVHandleTests.makeHandle(videoOutput: "libmpv", keepOpen: true, recorder: EventRecorder())
        let renderContext = try MPVRenderContext.software(handle: handle)

        #expect(throws: MPVLifecycleError.renderContextStillAlive) { try handle.destroy() }

        renderContext.free()
        try handle.destroy()
    }

    @Test func refusesASecondRenderContext() throws {
        let handle = try MPVHandleTests.makeHandle(videoOutput: "libmpv", keepOpen: true, recorder: EventRecorder())
        let first = try MPVRenderContext.software(handle: handle)

        #expect(throws: MPVLifecycleError.renderContextAlreadyExists) {
            _ = try MPVRenderContext.software(handle: handle)
        }

        first.free()
        let second = try MPVRenderContext.software(handle: handle)
        second.free()
        try handle.destroy()
    }

    @Test func rendersDecodedFramesInSoftware() async throws {
        let handle = try MPVHandleTests.makeHandle(videoOutput: "libmpv", keepOpen: true, recorder: EventRecorder())
        let renderContext = try MPVRenderContext.software(handle: handle)
        defer {
            renderContext.free()
            try? handle.destroy()
        }
        try handle.command(["loadfile", try Media.clip().video.path])

        var litPixels = 0
        let deadline = ContinuousClock.now + .seconds(10)
        while litPixels == 0, ContinuousClock.now < deadline {
            if renderContext.takePendingUpdate(), let pixels = renderContext.renderSoftware(width: 64, height: 36) {
                litPixels = stride(from: 0, to: pixels.count, by: 4).filter {
                    pixels[$0] > 16 || pixels[$0 + 1] > 16 || pixels[$0 + 2] > 16
                }.count
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(litPixels > 0)
    }
}
