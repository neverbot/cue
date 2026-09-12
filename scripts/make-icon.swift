// Draws Cue's placeholder app icon into an .iconset directory.
// usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / 1024

    // Rounded-square plate inside the standard 100 pt margin of a 1024 pt canvas.
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824).applying(CGAffineTransform(scaleX: scale, y: scale))
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.26, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.09, alpha: 1)
    )!.draw(in: platePath, angle: -90)

    // Three queue bars on the left, a play triangle on the right.
    NSColor(calibratedWhite: 1, alpha: 0.55).setFill()
    for index in 0..<3 {
        let bar = NSRect(x: 250, y: 380 + CGFloat(index) * 110, width: 220, height: 56)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
        NSBezierPath(roundedRect: bar, xRadius: 28 * scale, yRadius: 28 * scale).fill()
    }
    NSColor.white.setFill()
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: 540 * scale, y: 340 * scale))
    triangle.line(to: NSPoint(x: 540 * scale, y: 684 * scale))
    triangle.line(to: NSPoint(x: 800 * scale, y: 512 * scale))
    triangle.close()
    triangle.fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
