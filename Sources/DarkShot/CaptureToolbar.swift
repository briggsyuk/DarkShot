import AppKit

@MainActor
final class CaptureToolbar: NSVisualEffectView {
    static let preferredSize = CGSize(width: 300, height: 68)

    var onTool: ((DrawingTool) -> Void)?
    var onColor: ((NSColor) -> Void)?
    var onWidth: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    private var toolButtons: [DrawingTool: NSButton] = [:]
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let swatch = NSColorWell()

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize))
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        if #available(macOS 26.0, *) { prefersCompactControlSizeMetrics = true }
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 1

        let tools = NSStackView()
        tools.orientation = .horizontal
        tools.spacing = 2
        tools.distribution = .equalSpacing
        for tool in DrawingTool.allCases {
            let button = makeButton(symbol: tool.symbol, title: tool.title,
                                    action: #selector(chooseTool(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            tools.addArrangedSubview(button)
            toolButtons[tool] = button
        }
        tools.addArrangedSubview(divider())
        configure(undoButton, symbol: "arrow.uturn.backward", title: "Undo (⌘Z)", action: #selector(undoAction))
        configure(redoButton, symbol: "arrow.uturn.forward", title: "Redo (⇧⌘Z)", action: #selector(redoAction))
        tools.addArrangedSubview(undoButton)
        tools.addArrangedSubview(redoButton)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 6
        swatch.controlSize = .small
        swatch.colorWellStyle = .minimal
        swatch.color = .systemRed
        swatch.target = self
        swatch.action = #selector(colorChanged)
        swatch.toolTip = "Annotation color"
        swatch.setAccessibilityLabel("Annotation color")
        swatch.widthAnchor.constraint(equalToConstant: 24).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 24).isActive = true
        actions.addArrangedSubview(swatch)

        let slider = NSSlider(value: 3, minValue: 1, maxValue: 10,
                              target: self, action: #selector(widthChanged(_:)))
        slider.toolTip = "Stroke width (− / +)"
        slider.setAccessibilityLabel("Stroke width")
        slider.controlSize = .small
        slider.widthAnchor.constraint(equalToConstant: 64).isActive = true
        slider.heightAnchor.constraint(equalToConstant: 24).isActive = true
        actions.addArrangedSubview(slider)
        widthSlider = slider
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.addArrangedSubview(spacer)
        actions.addArrangedSubview(divider())
        actions.addArrangedSubview(makeButton(symbol: "doc.on.doc",
                                              title: "Copy screenshot and close (⌘C or Return)",
                                              action: #selector(copyAction)))
        actions.addArrangedSubview(makeButton(symbol: "square.and.arrow.down",
                                              title: "Save screenshot (⌘S)",
                                              action: #selector(saveAction)))
        actions.addArrangedSubview(makeButton(symbol: "xmark", title: "Cancel (Esc)", action: #selector(cancelAction)))

        let stack = NSStackView(views: [tools, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            tools.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        update(tool: .arrow, canUndo: false, canRedo: false)
    }

    private var widthSlider: NSSlider?

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(tool: DrawingTool, canUndo: Bool, canRedo: Bool) {
        for (key, button) in toolButtons {
            button.contentTintColor = key == tool ? .systemTeal : .white
            button.state = key == tool ? .on : .off
        }
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    func setWidth(_ width: CGFloat) { widthSlider?.doubleValue = Double(width) }
    func closeColorPicker() { swatch.deactivate(); NSColorPanel.shared.orderOut(nil) }

    private func divider() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return view
    }

    private func configure(_ button: NSButton, symbol: String, title: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        button.title = ""
        button.controlSize = .small
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = self
        button.action = action
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private func makeButton(symbol: String, title: String, action: Selector) -> NSButton {
        let button = NSButton()
        configure(button, symbol: symbol, title: title, action: action)
        return button
    }

    @objc private func chooseTool(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = DrawingTool(rawValue: raw) else { return }
        onTool?(tool)
    }
    @objc private func colorChanged() { onColor?(swatch.color) }
    @objc private func widthChanged(_ sender: NSSlider) { onWidth?(CGFloat(sender.doubleValue)) }
    @objc private func undoAction() { onUndo?() }
    @objc private func redoAction() { onRedo?() }
    @objc private func copyAction() { onCopy?() }
    @objc private func saveAction() { onSave?() }
    @objc private func cancelAction() { onCancel?() }
}
