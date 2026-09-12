import CueMPV
import Foundation
import Testing

/// Handle and render-context lifecycle checks that need no media, display or network: the LGPL build marker and the
/// shutdown-ordering guards. Always runs (`scripts/test.sh` already refuses to start without the dylib), unlike the
/// media-dependent suites in `MPVHandleTests` and `MPVRenderContextTests`, which stay gated behind `CUE_MPV_TESTS`.
@Suite(.serialized)
struct MPVLifecycleTests {
    @Test func reportsAnLGPLBuild() throws {
        let recorder = EventRecorder()
        let handle = try MPVHandleTests.makeHandle(videoOutput: "null", keepOpen: false, recorder: recorder)
        defer { try? handle.destroy() }
        let configuration = try #require(handle.propertyString("mpv-configuration"))
        #expect(configuration.contains("-Dgpl=false"))
    }

    @Test func refusesASecondDestroy() throws {
        let handle = try MPVHandleTests.makeHandle(videoOutput: "null", keepOpen: false, recorder: EventRecorder())
        try handle.destroy()
        #expect(throws: MPVLifecycleError.alreadyDestroyed) { try handle.destroy() }
    }

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
}
