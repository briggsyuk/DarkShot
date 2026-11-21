import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                            xRadius: 184, yRadius: 184)
    NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.09, blue: 0.14, alpha: 1),
               ending: NSColor(srgbRed: 0.16, green: 0.21, blue: 0.28, alpha: 1))!
        .draw(in: tile, angle: 90)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    tile.lineWidth = 2
    tile.stroke()
    let corners = NSBezierPath()
    corners.lineWidth = 30
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    for (x, y, dx, dy): (CGFloat, CGFloat, CGFloat, CGFloat) in [
        (296, 310, 1, 1), (728, 310, -1, 1), (296, 714, 1, -1), (728, 714, -1, -1)
    ] {
        corners.move(to: CGPoint(x: x, y: y + dy * 96))
        corners.line(to: CGPoint(x: x, y: y))
        corners.line(to: CGPoint(x: x + dx * 96, y: y))
    }
    NSColor(srgbRed: 0.22, green: 0.88, blue: 0.81, alpha: 1).setStroke()
    corners.stroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 32
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: CGPoint(x: 423, y: 423))
    arrow.line(to: CGPoint(x: 603, y: 603))
    arrow.move(to: CGPoint(x: 490, y: 603))
    arrow.line(to: CGPoint(x: 603, y: 603))
    arrow.line(to: CGPoint(x: 603, y: 490))
    NSColor.white.setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let path = "\(destination)/icon_\(size)x\(size)\(suffix).png"
        try render(size: size * scale).write(to: URL(fileURLWithPath: path))
    }
}
