import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let recorder: ShortcutRecorder
    private let message = NSTextField(wrappingLabelWithString: "")
    private let loginToggle = NSButton(checkboxWithTitle: "Launch DarkShot at login", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let loginItem: LaunchAtLogin
    private let applyShortcut: (ShortcutCombination) -> String?
    private var activationObserver: NSObjectProtocol?

    init(combination: ShortcutCombination, loginItem: LaunchAtLogin,
         onApply: @escaping (ShortcutCombination) -> String?,
         onRecordingChanged: @escaping (Bool) -> Void) {
        recorder = ShortcutRecorder(combination: combination)
        self.loginItem = loginItem
        applyShortcut = onApply
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 470, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DarkShot Settings"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        window.delegate = self
        let content = NSView()
        window.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        let heading = NSTextField(labelWithString: "Capture shortcut")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(heading)
        let row = NSStackView()
        row.spacing = 12
        row.addArrangedSubview(recorder)
        let reset = NSButton(title: "Reset to Default", target: self, action: #selector(resetShortcut))
        reset.bezelStyle = .rounded
        row.addArrangedSubview(reset)
        stack.addArrangedSubview(row)
        message.font = .systemFont(ofSize: 12)
        message.preferredMaxLayoutWidth = 422
        message.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        stack.addArrangedSubview(message)
        let divider = NSBox()
        divider.boxType = .separator
        stack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        loginToggle.target = self
        loginToggle.action = #selector(toggleLogin)
        stack.addArrangedSubview(loginToggle)
        loginStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        loginStatus.preferredMaxLayoutWidth = 422
        stack.addArrangedSubview(loginStatus)
        let systemSettings = NSButton(title: "Open macOS Login Items…", target: self, action: #selector(openLoginSettings))
        systemSettings.bezelStyle = .rounded
        stack.addArrangedSubview(systemSettings)
        recorder.onApply = onApply
        recorder.onRecordingChanged = onRecordingChanged
        recorder.onMessage = { [weak self] text in self?.showMessage(text) }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLoginStatus() }
        }
        showMessage(nil)
        refreshLoginStatus()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refreshLoginStatus()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMessage(_ text: String?) {
        message.stringValue = text ?? "Click the shortcut to change it. Use Control, Option, or Command with a key, or an F-key on its own."
        message.textColor = text == nil ? .secondaryLabelColor : .systemOrange
    }

    @objc private func resetShortcut() {
        recorder.cancelRecording()
        if let error = applyShortcut(.default) { showMessage(error); return }
        recorder.combination = .default
        showMessage(nil)
    }

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
        do {
            try loginItem.setEnabled(enabled)
            refreshLoginStatus()
            return loginItem.status == (enabled ? .enabled : .notRegistered)
        } catch {
            refreshLoginStatus()
            loginStatus.stringValue = "Couldn’t change login startup: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshLoginStatus() {
        switch loginItem.status {
        case .enabled:
            loginToggle.state = .on
            loginStatus.stringValue = "DarkShot will start quietly in the menu bar when you sign in."
        case .requiresApproval:
            loginToggle.state = .on
            loginStatus.stringValue = "macOS approval is needed. Enable DarkShot in Login Items below."
        case .notRegistered:
            loginToggle.state = .off
            loginStatus.stringValue = "Off. Turn this on to have DarkShot ready when you sign in."
        case .notFound:
            loginToggle.state = .off
            loginStatus.stringValue = "macOS couldn’t find this app. Keep DarkShot in a permanent location and try again."
        @unknown default:
            loginToggle.state = .off
            loginStatus.stringValue = "Check DarkShot’s startup status in macOS Login Items."
        }
    }

    @objc private func toggleLogin() { setLaunchAtLoginEnabled(loginToggle.state == .on) }
    @objc private func openLoginSettings() { recorder.cancelRecording(); loginItem.openSettings() }
    func windowWillClose(_ notification: Notification) { recorder.cancelRecording() }
    func windowDidResignKey(_ notification: Notification) { recorder.cancelRecording() }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
}
