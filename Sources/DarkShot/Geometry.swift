import Foundation

enum SelectionGeometry {
    static func rectangle(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        let a = clamped(start, to: bounds)
        let b = clamped(end, to: bounds)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY))
    }

    static func moved(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: min(max(rect.minX + delta.x, bounds.minX), bounds.maxX - rect.width),
               y: min(max(rect.minY + delta.y, bounds.minY), bounds.maxY - rect.height),
               width: rect.width, height: rect.height)
    }

    /// Clockwise from top-left: corner, edge midpoint, corner, ...
    static func resized(_ rect: CGRect, handle: Int, to point: CGPoint, within bounds: CGRect) -> CGRect {
        let p = clamped(point, to: bounds)
        var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        if [0, 6, 7].contains(handle) { left = p.x }
        if [2, 3, 4].contains(handle) { right = p.x }
        if [0, 1, 2].contains(handle) { top = p.y }
        if [4, 5, 6].contains(handle) { bottom = p.y }
        return rectangle(from: CGPoint(x: left, y: top), to: CGPoint(x: right, y: bottom), within: bounds)
    }

    /// AppKit canvas coordinates are top-left based here. Round outward to retain edge pixels.
    static func pixelRect(_ rect: CGRect, canvas: CGSize, pixels: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        let sx = pixels.width / canvas.width
        let sy = pixels.height / canvas.height
        let x = floor(rect.minX * sx)
        let y = floor(rect.minY * sy)
        return CGRect(x: x, y: y, width: ceil(rect.maxX * sx) - x,
                      height: ceil(rect.maxY * sy) - y)
            .intersection(CGRect(origin: .zero, size: pixels))
    }
}
