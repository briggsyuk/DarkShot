import AppKit
import Foundation

/// Uses only the macOS SDK, so full Xcode / XCTest is not required.
@main
struct Checks {
    static var failures = 0
    static var count = 0

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        count += 1
        if condition() { print("PASS \(name)") }
        else { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        geometry()
        renderer()
        print("\(count - failures)/\(count) checks passed")
        exit(failures == 0 ? 0 : 1)
    }

    static func geometry() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        check("reverse selection", SelectionGeometry.rectangle(
            from: CGPoint(x: 80, y: 70), to: CGPoint(x: 10, y: 20), within: bounds)
              == CGRect(x: 10, y: 20, width: 70, height: 50))
        check("clamped selection", SelectionGeometry.rectangle(
            from: CGPoint(x: -20, y: 10), to: CGPoint(x: 200, y: 120), within: bounds)
              == CGRect(x: 0, y: 10, width: 100, height: 70))
        check("move preserves size at boundary", SelectionGeometry.moved(
            CGRect(x: 30, y: 20, width: 60, height: 40), by: CGPoint(x: 100, y: -100), within: bounds)
              == CGRect(x: 40, y: 0, width: 60, height: 40))
        let rect = CGRect(x: 20, y: 20, width: 40, height: 30)
        check("top edge resize preserves width", SelectionGeometry.resized(rect, handle: 1, to: CGPoint(x: 0, y: 10), within: bounds)
              == CGRect(x: 20, y: 10, width: 40, height: 40))
        check("right edge resize preserves height", SelectionGeometry.resized(rect, handle: 3, to: CGPoint(x: 90, y: 0), within: bounds)
              == CGRect(x: 20, y: 20, width: 70, height: 30))
        check("corner resize crosses opposite corner", SelectionGeometry.resized(rect, handle: 0, to: CGPoint(x: 80, y: 70), within: bounds)
              == CGRect(x: 60, y: 50, width: 20, height: 20))
        check("resize clamps to display", SelectionGeometry.resized(rect, handle: 4, to: CGPoint(x: 180, y: 200), within: bounds)
              == CGRect(x: 20, y: 20, width: 80, height: 60))
        check("retina crop", SelectionGeometry.pixelRect(
            CGRect(x: 10, y: 20, width: 30, height: 40),
            canvas: CGSize(width: 100, height: 100), pixels: CGSize(width: 200, height: 200))
              == CGRect(x: 20, y: 40, width: 60, height: 80))
        check("fractional crop rounds outward", SelectionGeometry.pixelRect(
            CGRect(x: 0.2, y: 0.7, width: 4.1, height: 3.1),
            canvas: CGSize(width: 100, height: 100), pixels: CGSize(width: 200, height: 200))
              == CGRect(x: 0, y: 1, width: 9, height: 7))
        check("invalid canvas", SelectionGeometry.pixelRect(
            .zero, canvas: .zero, pixels: CGSize(width: 200, height: 200)) == .zero)
    }

    static func sampleImage() -> CGImage {
        let context = CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 80, width: 200, height: 80))
        return context.makeImage()!
    }

    static func renderer() {
        let image = sampleImage()
        let size = CGSize(width: 100, height: 80)
        guard let full = ScreenshotRenderer.render(
            image: image, canvasSize: size, selection: CGRect(origin: .zero, size: size), annotations: []),
              let crop = ScreenshotRenderer.render(
                image: image, canvasSize: size, selection: CGRect(x: 10, y: 5, width: 20, height: 20), annotations: []) else {
            check("renderer produces a bitmap", false)
            return
        }
        check("export retains retina resolution", full.pixelsWide == 200 && full.pixelsHigh == 160)
        check("PNG export", full.representation(using: .png, properties: [:]) != nil)
        check("TIFF clipboard export", full.tiffRepresentation != nil)
        check("image top stays at top", rgb(full, 20, 20).redComponent > 0.9)
        check("image bottom stays at bottom", rgb(full, 20, 140).blueComponent > 0.9)
        check("crop size", crop.pixelsWide == 40 && crop.pixelsHigh == 40)
        check("crop uses top-left coordinates", rgb(crop, 10, 10).redComponent > 0.9)
        let line = Annotation(tool: .line, points: [CGPoint(x: 25, y: 20), CGPoint(x: 45, y: 20)], color: .green, width: 4)
        if let result = ScreenshotRenderer.render(
            image: image, canvasSize: size, selection: CGRect(x: 20, y: 10, width: 40, height: 30), annotations: [line]) {
            check("annotation scales and translates with crop", rgb(result, 20, 20).greenComponent > 0.9 && rgb(result, 20, 20).redComponent < 0.1)
            check("annotation leaves other pixels alone", rgb(result, 20, 45).redComponent > 0.9)
        } else { check("annotation export", false) }
        for tool in DrawingTool.allCases where tool != .select {
            let annotation = Annotation(tool: tool, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 30)],
                                        color: .white, width: 3, text: "Test")
            check("\(tool.rawValue) renders", ScreenshotRenderer.render(
                image: image, canvasSize: size, selection: CGRect(origin: .zero, size: size), annotations: [annotation]) != nil)
        }
        check("empty crop fails gracefully", ScreenshotRenderer.render(
            image: image, canvasSize: size, selection: .zero, annotations: []) == nil)
    }

    static func rgb(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    }
}
