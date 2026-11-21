import AppKit

@MainActor
final class CaptureCanvas: NSView, NSTextFieldDelegate {
    enum ExportAction { case copy, save }
    private enum Gesture {
        case create(CGPoint)
        case move(CGPoint, CGRect)
        case resize(Int, CGRect)
        case draw
    }

    let image: CGImage
    var onBeginSelection: (() -> Void)?
    var onReselect: (() -> Void)?
    var onExport: ((NSBitmapImageRep, ExportAction) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var selection: CGRect?
    private var gesture: Gesture?
    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var draft: Annotation?
    private var tool: DrawingTool = .arrow
    private var color: NSColor = .systemRed
    private var strokeWidth: CGFloat = 3
    private var textField: NSTextField?
    private var textOrigin: CGPoint?
    private var textColor: NSColor = .systemRed
    private var textWidth: CGFloat = 3
    private let toolbar = CaptureToolbar()
    private var pointer: CGPoint = .zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage, size: CGSize) {
        self.image = image
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        setAccessibilityLabel("Screenshot selection and annotation canvas")
        toolbar.isHidden = true
        addSubview(toolbar)
        toolbar.onTool = { [weak self] tool in
            self?.commitText()
            self?.tool = tool
            self?.window?.makeFirstResponder(self)
            self?.refresh()
        }
        toolbar.onColor = { [weak self] in self?.color = $0 }
        toolbar.onWidth = { [weak self] in self?.strokeWidth = $0 }
        toolbar.onUndo = { [weak self] in self?.undoAnnotation() }
        toolbar.onRedo = { [weak self] in self?.redoAnnotation() }
        toolbar.onCopy = { [weak self] in self?.export(.copy) }
        toolbar.onSave = { [weak self] in self?.export(.save) }
        toolbar.onCancel = { [weak self] in self?.onCancel?() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select && selection != nil ? .arrow : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.46).setFill()
        let shade = NSBezierPath(rect: bounds)
        if let selection {
            shade.appendRect(selection)
            shade.windingRule = .evenOdd
        }
        shade.fill()

        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            annotations.forEach { $0.draw() }
            draft?.draw()
            NSGraphicsContext.restoreGraphicsState()

            let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            NSColor.white.withAlphaComponent(0.95).setStroke()
            border.lineWidth = 1
            border.stroke()
            for handle in handles(for: selection) {
                NSColor.white.setFill()
                NSBezierPath(roundedRect: handle, xRadius: 1.5, yRadius: 1.5).fill()
            }
            drawDimensions(selection)
        } else {
            let text = "Drag to capture an area     ·     Esc to cancel"
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
            let x = min(max(pointer.x + 20, 16), bounds.width - size.width - 32)
            let y = min(max(pointer.y + 24, 40), bounds.height - 64)
            drawBadge(text, at: CGPoint(x: x, y: y))
        }
    }

    private func drawDimensions(_ rect: CGRect) {
        let pixels = SelectionGeometry.pixelRect(
            rect, canvas: bounds.size, pixels: CGSize(width: image.width, height: image.height))
        let text = "\(Int(pixels.width)) × \(Int(pixels.height))"
        drawBadge(text, at: CGPoint(x: max(8, rect.minX), y: rect.minY >= 36 ? rect.minY - 31 : rect.minY + 8))
    }

    private func drawBadge(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: point.x, y: point.y, width: size.width + 18, height: 25)
        NSColor(calibratedWhite: 0.10, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 9, y: rect.minY + 5), withAttributes: attributes)
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        if selection == nil { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let point = SelectionGeometry.clamped(convert(event.locationInWindow, from: nil), to: bounds)
        pointer = point
        if let selection {
            if let index = handles(for: selection).firstIndex(where: { $0.insetBy(dx: -5, dy: -5).contains(point) }) {
                gesture = .resize(index, selection)
                toolbar.isHidden = true
                return
            }
            guard selection.contains(point) else {
                // Do not accidentally discard annotations: use N to explicitly reselect.
                NSSound.beep()
                return
            }
            if tool == .select {
                gesture = .move(point, selection)
                toolbar.isHidden = true
            } else if tool == .text {
                beginText(at: point)
            } else {
                draft = Annotation(tool: tool, points: [point], color: color, width: strokeWidth)
                gesture = .draw
            }
        } else {
            onBeginSelection?()
            selection = CGRect(origin: point, size: .zero)
            gesture = .create(point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = SelectionGeometry.clamped(convert(event.locationInWindow, from: nil), to: bounds)
        switch gesture {
        case .create(let origin):
            selection = SelectionGeometry.rectangle(from: origin, to: point, within: bounds)
        case .resize(let handle, let rect):
            selection = SelectionGeometry.resized(rect, handle: handle, to: point, within: bounds)
        case .move(let origin, let rect):
            selection = SelectionGeometry.moved(rect, by: CGPoint(x: point.x - origin.x, y: point.y - origin.y), within: bounds)
        case .draw:
            guard let selection, let first = draft?.points.first else { return }
            var end = SelectionGeometry.clamped(point, to: selection)
            if event.modifierFlags.contains(.shift), draft?.tool != .pen, draft?.tool != .highlighter {
                if draft?.tool == .rectangle || draft?.tool == .ellipse {
                    let length = min(abs(end.x - first.x), abs(end.y - first.y))
                    end = CGPoint(x: first.x + (end.x < first.x ? -length : length),
                                  y: first.y + (end.y < first.y ? -length : length))
                } else {
                    let distance = hypot(end.x - first.x, end.y - first.y)
                    let angle = (atan2(end.y - first.y, end.x - first.x) / (.pi / 4)).rounded() * (.pi / 4)
                    end = SelectionGeometry.clamped(
                        CGPoint(x: first.x + cos(angle) * distance, y: first.y + sin(angle) * distance), to: selection)
                }
            }
            if draft?.tool == .pen || draft?.tool == .highlighter {
                draft?.points.append(end)
            } else {
                draft?.points = [first, end]
            }
        case nil: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if case .draw = gesture, let draft {
            annotations.append(draft)
            redoStack.removeAll()
        }
        draft = nil
        if let selection, selection.width < 3 || selection.height < 3 {
            if case .resize(_, let original) = gesture { self.selection = original }
            else { self.selection = nil }
        }
        gesture = nil
        refresh()
    }

    private func handlePoints(for rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
    }

    private func handles(for rect: CGRect) -> [CGRect] {
        handlePoints(for: rect).map { CGRect(x: $0.x - 3, y: $0.y - 3, width: 6, height: 6) }
    }

    private func refresh() {
        toolbar.update(tool: tool, canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
        toolbar.isHidden = selection == nil
        if let selection {
            let width = min(CaptureToolbar.preferredSize.width, bounds.width - 16)
            let height = CaptureToolbar.preferredSize.height
            let x = min(max(8, selection.maxX - width), bounds.width - width - 8)
            var y = selection.maxY + 8
            if y + height > bounds.height - 8 { y = selection.minY - height - 8 }
            if y < 8 { y = max(8, bounds.height - height - 8) }
            toolbar.frame = CGRect(x: x, y: y, width: width, height: height)
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func beginText(at point: CGPoint) {
        guard let selection else { return }
        let field = NSTextField(frame: CGRect(
            x: point.x, y: point.y, width: max(40, selection.maxX - point.x),
            height: max(30, strokeWidth * 5 + 18)))
        field.placeholderString = "Type, then Return"
        field.font = .systemFont(ofSize: max(16, strokeWidth * 5 + 10), weight: .semibold)
        field.textColor = color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        field.focusRingType = .none
        field.delegate = self
        textOrigin = point
        textColor = color
        textWidth = strokeWidth
        textField = field
        addSubview(field)
        window?.makeFirstResponder(field)
    }

    private func commitText() {
        guard let field = textField else { return }
        let text = field.currentEditor()?.string ?? field.stringValue
        textField = nil
        window?.makeFirstResponder(self)
        field.removeFromSuperview()
        if !text.isEmpty, let origin = textOrigin {
            annotations.append(Annotation(tool: .text, points: [origin], color: textColor,
                                          width: textWidth, text: text))
            redoStack.removeAll()
        }
        textOrigin = nil
        window?.makeFirstResponder(self)
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitText()
            return true
        }
        return false
    }

    private func undoAnnotation() {
        commitText()
        if let last = annotations.popLast() { redoStack.append(last) }
        refresh()
    }

    private func redoAnnotation() {
        if let last = redoStack.popLast() { annotations.append(last) }
        refresh()
    }

    private func export(_ action: ExportAction) {
        commitText()
        guard let selection, let bitmap = ScreenshotRenderer.render(
            image: image, canvasSize: bounds.size, selection: selection, annotations: annotations) else {
            NSSound.beep()
            return
        }
        toolbar.closeColorPicker()
        onExport?(bitmap, action)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let the field editor handle normal copy/paste and undo while typing.
        if textField != nil { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": export(.copy); return true
            case "s": export(.save); return true
            case "z":
                event.modifierFlags.contains(.shift) ? redoAnnotation() : undoAnnotation()
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        if event.keyCode == 36 { export(.copy); return }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let tools: [String: DrawingTool] = [
            "v": .select, "p": .pen, "l": .line, "a": .arrow,
            "r": .rectangle, "o": .ellipse, "h": .highlighter, "t": .text
        ]
        if let chosen = tools[key] { tool = chosen; refresh(); return }
        if key == "+" || key == "=" || key == "-" {
            strokeWidth = min(10, max(1, strokeWidth + (key == "-" ? -1 : 1)))
            toolbar.setWidth(strokeWidth)
            return
        }
        if key == "n" {
            selection = nil
            annotations.removeAll()
            redoStack.removeAll()
            refresh()
            onReselect?()
            return
        }
        if event.keyCode == 51 { undoAnnotation(); return }
        if let selection, [123, 124, 125, 126].contains(event.keyCode) {
            let step: CGFloat = event.modifierFlags.contains(.option) ? 10 : 1
            let delta = CGPoint(x: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,
                                y: event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0)
            if event.modifierFlags.contains(.shift) {
                self.selection = CGRect(x: selection.minX, y: selection.minY,
                                        width: min(bounds.maxX - selection.minX, max(3, selection.width + delta.x)),
                                        height: min(bounds.maxY - selection.minY, max(3, selection.height + delta.y)))
            } else {
                self.selection = SelectionGeometry.moved(selection, by: delta, within: bounds)
            }
            refresh()
            return
        }
        super.keyDown(with: event)
    }

    func tearDown() { toolbar.closeColorPicker() }
}
