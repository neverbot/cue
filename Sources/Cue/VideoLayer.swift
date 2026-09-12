import AppKit
import CueMPV
import OpenGL.GL3
import os
import QuartzCore

/// The only place that touches OpenGL. An asynchronous `CAOpenGLLayer`: Core Animation polls `canDraw` at the display
/// rate on its own thread, and mpv's update callback only raises a flag, so rendering never blocks the main thread and
/// never calls blocking mpv APIs.
///
/// While the window is occluded Core Animation throttles the layer, so a render-queue timer consumes mpv's frames with
/// `MPV_RENDER_PARAM_SKIP_RENDERING` instead.
///
/// Locking: whoever touches the render context takes the CGL context lock first and `renderLock` second, always in
/// that order.
final class VideoLayer: CAOpenGLLayer, @unchecked Sendable {
    // @unchecked: `renderLock` guards the render context and GL context; `hiddenTimer` is only touched on the main thread.

    private let handle: MPVHandle
    private let renderLock = NSLock()
    private var renderContext: MPVRenderContext?
    private var glContext: CGLContextObj?
    private var forceDraw = false
    private var isTornDown = false
    private var pixelFormat: NSOpenGLPixelFormat?
    private let renderQueue = DispatchQueue(label: "cue.video.hidden-render")
    private var hiddenTimer: DispatchSourceTimer?
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "video")

    init(handle: MPVHandle) {
        self.handle = handle
        super.init()
        isAsynchronous = true
        needsDisplayOnBoundsChange = true
        backgroundColor = NSColor.black.cgColor
    }

    override init(layer: Any) {
        guard let other = layer as? VideoLayer else { fatalError("VideoLayer copied from \(type(of: layer))") }
        handle = other.handle
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var bounds: CGRect {
        didSet { renderLock.withLock { forceDraw = true } }
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAAllowOfflineRenderers),
            0,
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attributes), let object = format.cglPixelFormatObj else {
            return super.copyCGLPixelFormat(forDisplayMask: mask)
        }
        pixelFormat = format
        return object
    }

    /// Core Animation asks again when the display or the renderer changes. The layer keeps one CGL context and one
    /// render context for its whole life: later calls only take another reference to the same context.
    override func copyCGLContext(forPixelFormat pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        if let existing = renderLock.withLock({ glContext }) {
            return CGLRetainContext(existing)
        }
        let context = super.copyCGLContext(forPixelFormat: pixelFormat)
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)
        CGLLockContext(context)
        CGLSetCurrentContext(context)
        do {
            // mpv requires its OpenGL context to be current while the render context is created.
            let created = try MPVRenderContext.openGL(handle: handle)
            renderLock.withLock {
                renderContext = created
                glContext = context
            }
        } catch {
            logger.error("Could not create the mpv render context: \(String(describing: error), privacy: .public)")
        }
        CGLSetCurrentContext(nil)
        CGLUnlockContext(context)
        return context
    }

    override func canDraw(
        inCGLContext context: CGLContextObj,
        pixelFormat: CGLPixelFormatObj,
        forLayerTime layerTime: CFTimeInterval,
        displayTime: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        renderLock.withLock {
            guard !isTornDown, let renderContext else { return false }
            let forced = forceDraw
            forceDraw = false
            return renderContext.takePendingUpdate() || forced
        }
    }

    override func draw(
        inCGLContext context: CGLContextObj,
        pixelFormat: CGLPixelFormatObj,
        forLayerTime layerTime: CFTimeInterval,
        displayTime: UnsafePointer<CVTimeStamp>?
    ) {
        CGLLockContext(context)
        defer { CGLUnlockContext(context) }
        renderLock.withLock {
            guard !isTornDown, let renderContext else { return }
            var framebuffer: GLint = 0
            glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &framebuffer)
            var viewport = [GLint](repeating: 0, count: 4)
            glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
            renderContext.renderOpenGL(fbo: framebuffer, width: viewport[2], height: viewport[3])
            super.draw(inCGLContext: context, pixelFormat: pixelFormat, forLayerTime: layerTime, displayTime: displayTime)
        }
    }

    /// Main thread. Visible: Core Animation drives drawing. Hidden: frames are consumed without drawing.
    func setVisible(_ visible: Bool) {
        if visible {
            hiddenTimer?.cancel()
            hiddenTimer = nil
            isAsynchronous = true
            setNeedsDisplay()
        } else if hiddenTimer == nil {
            isAsynchronous = false
            let timer = DispatchSource.makeTimerSource(queue: renderQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(10))
            timer.setEventHandler { [weak self] in self?.skipPendingFrame() }
            timer.resume()
            hiddenTimer = timer
        }
    }

    /// Main thread, before `MPVPlaybackEngine.shutdown()`: frees the render context with its GL context current.
    func teardown() {
        hiddenTimer?.cancel()
        hiddenTimer = nil
        renderQueue.sync {}
        isAsynchronous = false
        let context = renderLock.withLock { glContext }
        if let context {
            CGLLockContext(context)
            CGLSetCurrentContext(context)
        }
        renderLock.withLock {
            guard !isTornDown else { return }
            isTornDown = true
            renderContext?.free()
            renderContext = nil
        }
        if let context {
            CGLSetCurrentContext(nil)
            CGLUnlockContext(context)
        }
    }

    private func skipPendingFrame() {
        guard let context = renderLock.withLock({ isTornDown ? nil : glContext }) else { return }
        CGLLockContext(context)
        CGLSetCurrentContext(context)
        renderLock.withLock {
            guard !isTornDown, let renderContext, renderContext.takePendingUpdate() else { return }
            renderContext.renderOpenGL(fbo: 0, width: 1, height: 1, skip: true)
        }
        CGLSetCurrentContext(nil)
        CGLUnlockContext(context)
    }
}

/// Hosts `VideoLayer` (a layer-hosting view: no subviews).
final class VideoView: NSView {
    let videoLayer: VideoLayer

    init(handle: MPVHandle) {
        videoLayer = VideoLayer(handle: handle)
        super.init(frame: .zero)
        layer = videoLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoLayer.contentsScale = window?.backingScaleFactor ?? 1
    }
}
