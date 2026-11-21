import AppKit

@main
struct InteractionChecks {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let size = CGSize(width: 800, height: 600)
        let context = CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        let canvas = CaptureCanvas(image: context.makeImage()!, size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        window.makeFirstResponder(canvas)
        var count = 0
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            count += 1
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: size.height - y),
                               modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func key(_ text: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil,
                             characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        func drag(_ a: CGPoint, _ b: CGPoint) {
            canvas.mouseDown(with: mouse(.leftMouseDown, a.x, a.y))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, b.x, b.y))
            canvas.mouseUp(with: mouse(.leftMouseUp, b.x, b.y))
        }
        var began = false
        canvas.onBeginSelection = { began = true }
        drag(CGPoint(x: 40, y: 50), CGPoint(x: 400, y: 300))
        check("drag begins a capture selection", began)
        check("drag creates expected selection", canvas.selection == CGRect(x: 40, y: 50, width: 360, height: 250))
        let toolbar = canvas.subviews.compactMap { $0 as? CaptureToolbar }.first!
        check("toolbar appears after selection", !toolbar.isHidden)
        check("toolbar is inside display", canvas.bounds.contains(toolbar.frame))
        check("toolbar uses compact dimensions", toolbar.frame.size == CGSize(width: 300, height: 68))
        check("toolbar uses less than half the previous area", toolbar.frame.width * toolbar.frame.height < 490 * 98 / 2)
        canvas.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let buttons = descendants(toolbar).compactMap { $0 as? NSButton }
        check("compact toolbar retains every drawing tool", DrawingTool.allCases.allSatisfy { tool in
            buttons.contains { $0.identifier?.rawValue == tool.rawValue }
        })
        let controls = descendants(toolbar).compactMap { $0 as? NSControl }.filter { $0.toolTip != nil }
        check("compact controls fit without clipping", controls.allSatisfy {
            toolbar.bounds.contains($0.convert($0.bounds, to: toolbar))
        })
        let copyButton = buttons.first { $0.toolTip == "Copy screenshot and close (⌘C or Return)" }
        let saveButton = buttons.first { $0.toolTip == "Save screenshot (⌘S)" }
        check("icon export buttons retain tooltips", copyButton != nil && saveButton != nil)

        canvas.keyDown(with: key("p"))
        drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100))
        var exported: NSBitmapImageRep?
        var exportedAction: CaptureCanvas.ExportAction?
        canvas.onExport = { bitmap, action in exported = bitmap; exportedAction = action }
        canvas.keyDown(with: key("\r", code: 36))
        check("Return exports selection", exported?.pixelsWide == 720 && exported?.pixelsHigh == 500)
        check("drawn pen appears in export", exported!.colorAt(x: 150, y: 100)!.usingColorSpace(.deviceRGB)!.redComponent > 0.5)
        exportedAction = nil
        copyButton?.performClick(nil)
        if case .copy = exportedAction { check("compact copy button exports", true) }
        else { check("compact copy button exports", false) }
        exportedAction = nil
        saveButton?.performClick(nil)
        if case .save = exportedAction { check("compact save button exports", true) }
        else { check("compact save button exports", false) }

        check("Command-Z handled by canvas", canvas.performKeyEquivalent(with: key("z", flags: .command)))
        canvas.keyDown(with: key("\r", code: 36))
        check("undo removes annotation", exported!.colorAt(x: 150, y: 100)!.usingColorSpace(.deviceRGB)!.blueComponent > 0.9)
        _ = canvas.performKeyEquivalent(with: key("z", flags: [.command, .shift]))
        canvas.keyDown(with: key("\r", code: 36))
        check("redo restores annotation", exported!.colorAt(x: 150, y: 100)!.usingColorSpace(.deviceRGB)!.redComponent > 0.5)

        drag(CGPoint(x: 220, y: 50), CGPoint(x: 220, y: 30))
        check("top handle preserves width", canvas.selection == CGRect(x: 40, y: 30, width: 360, height: 270))
        canvas.keyDown(with: key("v"))
        drag(CGPoint(x: 200, y: 180), CGPoint(x: 220, y: 200))
        check("move tool moves crop", canvas.selection == CGRect(x: 60, y: 50, width: 360, height: 270))
        canvas.keyDown(with: key("", code: 124))
        check("arrow key nudges crop", canvas.selection?.minX == 61)
        canvas.keyDown(with: key("", code: 125, flags: [.shift, .option]))
        check("Shift-Option-arrow resizes by ten", canvas.selection?.height == 280)

        canvas.keyDown(with: key("t"))
        canvas.mouseDown(with: mouse(.leftMouseDown, 100, 150))
        let text = canvas.subviews.compactMap { $0 as? NSTextField }.first
        check("text tool starts inline editing", text != nil)
        text?.currentEditor()?.string = "DarkShot"
        text?.stringValue = "DarkShot"
        if let text {
            _ = canvas.control(text, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        }
        check("Return commits inline text", !canvas.subviews.contains(where: { $0 is NSTextField }))
        canvas.layoutSubtreeIfNeeded()
        if let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: ".build/checks/annotation-preview.png"))
            }
            check("full annotation UI renders", bitmap.pixelsWide > 0)
        } else { check("full annotation UI renders", false) }

        var reselected = false
        canvas.onReselect = { reselected = true }
        canvas.keyDown(with: key("n"))
        check("N clears crop and offers display reselection", canvas.selection == nil && reselected)
        check("toolbar hides when reselecting", toolbar.isHidden)
        var cancelled = false
        canvas.onCancel = { cancelled = true }
        canvas.keyDown(with: key("", code: 53))
        check("Escape cancels session", cancelled)
        canvas.tearDown()
        window.close()
        print("\(count - failures)/\(count) interaction checks passed")
        exit(failures == 0 ? 0 : 1)
    }
}
