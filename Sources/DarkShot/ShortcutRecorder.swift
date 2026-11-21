import AppKit

@MainActor
final class ShortcutRecorder: NSButton {
    var combination: ShortcutCombination {
        didSet { if !isRecording { title = combination.displayString } }
    }
    var onApply: ((ShortcutCombination) -> String?)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onMessage: ((String?) -> Void)?
    private(set) var isRecording = false
    override var acceptsFirstResponder: Bool { true }

    init(combination: ShortcutCombination) {
        self.combination = combination
        super.init(frame: .zero)
        title = combination.displayString
        bezelStyle = .rounded
        font = .systemFont(ofSize: 17, weight: .medium)
        target = self
        action = #selector(beginRecording)
        toolTip = "Click, then press a new capture shortcut. Escape cancels."
        setAccessibilityLabel("Capture keyboard shortcut")
        widthAnchor.constraint(equalToConstant: 220).isActive = true
        heightAnchor.constraint(equalToConstant: 38).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func beginRecording() {
        guard !isRecording else { return }
        window?.makeFirstResponder(self)
        isRecording = true
        title = "Press shortcut…"
        onMessage?("Press your new combination. Escape cancels.")
        onRecordingChanged?(true)
    }

    func cancelRecording() {
        guard isRecording else { return }
        finishRecording()
        onMessage?(nil)
    }

    private func finishRecording() {
        isRecording = false
        title = combination.displayString
        onRecordingChanged?(false)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 { cancelRecording(); return }
        guard !event.isARepeat else { return }
        let candidate = ShortcutCombination(event: event)
        if let message = candidate.validationMessage {
            onMessage?(message)
            return
        }
        if let error = onApply?(candidate) {
            onMessage?(error)
            return
        }
        combination = candidate
        finishRecording()
        onMessage?(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) } else { super.keyDown(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }
}
