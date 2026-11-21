import AppKit

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class CaptureSession {
    var onExport: ((NSBitmapImageRep, CaptureCanvas.ExportAction) -> Void)?
    var onCancel: (() -> Void)?
    private var panels: [CapturePanel] = []
    private var canvases: [CaptureCanvas] = []
    private var activePanel: CapturePanel?

    init(displays: [CapturedDisplay]) {
        for display in displays {
            let panel = CapturePanel(contentRect: display.screen.frame, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.setFrame(display.screen.frame, display: false)
            let canvas = CaptureCanvas(image: display.image, size: display.screen.frame.size)
            panel.contentView = canvas
            canvas.onBeginSelection = { [weak self, weak panel, weak canvas] in
                guard let self, let panel else { return }
                self.activePanel = panel
                for other in self.panels where other !== panel { other.orderOut(nil) }
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(canvas)
            }
            canvas.onExport = { [weak self] in self?.onExport?($0, $1) }
            canvas.onCancel = { [weak self] in self?.onCancel?() }
            canvas.onReselect = { [weak self] in
                self?.activePanel = nil
                self?.show()
            }
            panels.append(panel)
            canvases.append(canvas)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        for panel in panels { panel.orderFrontRegardless() }
        let pointer = NSEvent.mouseLocation
        let panel = activePanel ?? panels.first(where: { $0.frame.contains(pointer) }) ?? panels.first
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(panel?.contentView)
        // The native color picker must sit above the capture surface.
        NSColorPanel.shared.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
    }

    func hide() {
        canvases.forEach { $0.tearDown() }
        panels.forEach { $0.orderOut(nil) }
    }

    func restore() {
        if let activePanel {
            activePanel.makeKeyAndOrderFront(nil)
            activePanel.makeFirstResponder(activePanel.contentView)
        } else {
            show()
        }
    }

    func close() {
        hide()
        panels.forEach { $0.close() }
        panels.removeAll()
        canvases.removeAll()
    }
}
