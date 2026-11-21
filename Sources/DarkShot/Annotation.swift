import AppKit

enum DrawingTool: String, CaseIterable {
    case select, pen, line, arrow, rectangle, ellipse, highlighter, text

    var title: String {
        switch self {
        case .select: return "Move / resize (V)"
        case .pen: return "Pen (P)"
        case .line: return "Line (L)"
        case .arrow: return "Arrow (A)"
        case .rectangle: return "Rectangle (R)"
        case .ellipse: return "Ellipse (O)"
        case .highlighter: return "Highlighter (H)"
        case .text: return "Text (T)"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        }
    }
}

struct Annotation {
    let tool: DrawingTool
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat
    var text: String = ""

    func draw() {
        guard let first = points.first, let last = points.last else { return }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()

        switch tool {
        case .select: return
        case .text:
            let font = NSFont.systemFont(ofSize: max(16, width * 5 + 10), weight: .semibold)
            (text as NSString).draw(at: first, withAttributes: [
                .font: font, .foregroundColor: color
            ])
            return
        case .pen, .highlighter:
            if tool == .highlighter {
                color.withAlphaComponent(0.30).setStroke()
                path.lineWidth = width * 7
                path.lineCapStyle = .butt
            }
            path.move(to: first)
            for point in points.dropFirst() { path.line(to: point) }
            if points.count == 1 { path.line(to: CGPoint(x: first.x + 0.1, y: first.y)) }
        case .line, .arrow:
            path.move(to: first)
            path.line(to: last)
            if tool == .arrow {
                let angle = atan2(last.y - first.y, last.x - first.x)
                let length = max(12, width * 4)
                for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                    path.move(to: last)
                    path.line(to: CGPoint(x: last.x - length * cos(angle + offset),
                                          y: last.y - length * sin(angle + offset)))
                }
            }
        case .rectangle, .ellipse:
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                              width: abs(last.x - first.x), height: abs(last.y - first.y))
            if tool == .rectangle { path.appendRect(rect) } else { path.appendOval(in: rect) }
        }
        path.stroke()
    }
}

/// Render into a full-resolution, flipped bitmap so preview and export share the same drawing code.
enum ScreenshotRenderer {
    static func render(image: CGImage, canvasSize: CGSize, selection: CGRect,
                       annotations: [Annotation]) -> NSBitmapImageRep? {
        let pixelRect = SelectionGeometry.pixelRect(
            selection, canvas: canvasSize,
            pixels: CGSize(width: image.width, height: image.height))
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = image.cropping(to: pixelRect),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: cropped.width, pixelsHigh: cropped.height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        // Establish top-left drawing coordinates for annotations, matching the overlay.
        cg.translateBy(x: 0, y: CGFloat(cropped.height))
        cg.scaleBy(x: CGFloat(image.width) / canvasSize.width,
                   y: -CGFloat(image.height) / canvasSize.height)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let destination = CGRect(origin: .zero,
                                 size: CGSize(width: CGFloat(cropped.width) * canvasSize.width / CGFloat(image.width),
                                              height: CGFloat(cropped.height) * canvasSize.height / CGFloat(image.height)))
        let source = NSImage(cgImage: cropped, size: destination.size)
        source.draw(in: destination, from: .zero, operation: .copy,
                    fraction: 1, respectFlipped: true, hints: nil)
        let origin = CGPoint(x: pixelRect.minX * canvasSize.width / CGFloat(image.width),
                             y: pixelRect.minY * canvasSize.height / CGFloat(image.height))
        cg.translateBy(x: -origin.x, y: -origin.y)
        for annotation in annotations { annotation.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
