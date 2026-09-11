import CMpv
import Darwin
import Foundation
import os

nonisolated(unsafe) private let openGLLibrary = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY)

/// libmpv's render API bound to one `MPVHandle` (`vo=libmpv`).
///
/// Threading (render.h): create, render and free on the thread that owns the graphics context, with it current.
/// The update callback only raises a flag; it never calls into mpv.
public final class MPVRenderContext: @unchecked Sendable {
    // @unchecked: `raw` is only touched by the render thread (create/render/free); the flag is lock-protected.

    private var raw: OpaquePointer?
    private let handle: MPVHandle
    private let pendingUpdate = OSAllocatedUnfairLock(initialState: false)
    private var callbackRetain: Unmanaged<MPVRenderContext>?

    /// Creates an OpenGL render context. The caller's OpenGL context must be current.
    public static func openGL(handle: MPVHandle) throws -> MPVRenderContext {
        var initParams = mpv_opengl_init_params(
            get_proc_address: { _, name in
                guard let name else { return nil }
                return dlsym(openGLLibrary, name)
            },
            get_proc_address_ctx: nil
        )
        return try withUnsafeMutablePointer(to: &initParams) { initPointer in
            try MPVRenderContext(handle: handle, api: MPV_RENDER_API_TYPE_OPENGL, extra: [
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
            ])
        }
    }

    /// Creates a software render context (CPU rendering into memory). Used by headless tests.
    public static func software(handle: MPVHandle) throws -> MPVRenderContext {
        try MPVRenderContext(handle: handle, api: MPV_RENDER_API_TYPE_SW, extra: [])
    }

    private init(handle: MPVHandle, api: String, extra: [mpv_render_param]) throws {
        self.handle = handle
        try handle.renderContextCreated()
        var created: OpaquePointer?
        var advancedControl: Int32 = 1
        let status = api.withCString { apiName in
            withUnsafeMutablePointer(to: &advancedControl) { advancedPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiName)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: UnsafeMutableRawPointer(advancedPointer)),
                ] + extra + [mpv_render_param()]
                return mpv_render_context_create(&created, handle.raw, &params)
            }
        }
        guard status >= 0, let created else {
            handle.renderContextFreed()
            throw MPVError(code: status, operation: "mpv_render_context_create(\(api))")
        }
        raw = created
        callbackRetain = Unmanaged.passRetained(self)
        mpv_render_context_set_update_callback(created, { context in
            guard let context else { return }
            Unmanaged<MPVRenderContext>.fromOpaque(context).takeUnretainedValue().pendingUpdate.withLock { $0 = true }
        }, callbackRetain?.toOpaque())
    }

    /// True once since the last call if mpv asked for a redraw. Cheap and non-blocking: safe in `canDraw`.
    public func takePendingUpdate() -> Bool {
        pendingUpdate.withLock { pending in
            defer { pending = false }
            return pending
        }
    }

    /// Renders into the bound OpenGL framebuffer `fbo`. With `skip`, mpv advances its frame queue without drawing,
    /// which keeps timing intact while the window is hidden.
    public func renderOpenGL(fbo: Int32, width: Int32, height: Int32, skip: Bool = false) {
        guard let raw else { return }
        _ = mpv_render_context_update(raw)
        var target = mpv_opengl_fbo(fbo: fbo, w: width, h: height, internal_format: 0)
        var flipY: Int32 = 1
        var skipRendering: Int32 = skip ? 1 : 0
        withUnsafeMutablePointer(to: &target) { targetPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                withUnsafeMutablePointer(to: &skipRendering) { skipPointer in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(targetPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPointer)),
                        mpv_render_param(),
                    ]
                    _ = mpv_render_context_render(raw, &params)
                }
            }
        }
    }

    /// Renders the current frame as `rgb0` pixels (4 bytes per pixel). Returns nil when no frame was rendered.
    public func renderSoftware(width: Int, height: Int) -> [UInt8]? {
        guard let raw else { return nil }
        let flags = mpv_render_context_update(raw)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var size: [Int32] = [Int32(width), Int32(height)]
        var stride = width * 4
        let status = "rgb0".withCString { format in
            size.withUnsafeMutableBufferPointer { sizePointer in
                withUnsafeMutablePointer(to: &stride) { stridePointer in
                    pixels.withUnsafeMutableBytes { pixelPointer in
                        var params = [
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(sizePointer.baseAddress!)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: format)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePointer)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pixelPointer.baseAddress!),
                            mpv_render_param(),
                        ]
                        return mpv_render_context_render(raw, &params)
                    }
                }
            }
        }
        return status >= 0 ? pixels : nil
    }

    /// Frees the render context. Call before `MPVHandle.destroy()`, on the render thread, with the graphics context
    /// current (OpenGL).
    public func free() {
        guard let raw else { return }
        mpv_render_context_set_update_callback(raw, nil, nil)
        mpv_render_context_free(raw)
        self.raw = nil
        callbackRetain?.release()
        callbackRetain = nil
        handle.renderContextFreed()
    }
}
