import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let shortcut = GlobalShortcut()
    private var captureCombination = ShortcutCombination.load()
    private let loginItem = LaunchAtLogin()
    private var captureMenuItem: NSMenuItem?
    private var isRecordingShortcut = false
    private var settingsController: SettingsWindowController?
    private weak var welcomeShortcutLabel: NSTextField?
    private let captureService = CaptureService()
    private var session: CaptureSession?
    private var isCapturing = false
    private var isSaving = false
    private var welcomeWindow: NSWindow?
    private var previousApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "DarkShot")
        let menu = NSMenu()
        captureMenuItem = addItem("Capture an Area", action: #selector(captureArea), to: menu)
        menu.addItem(.separator())
        let privateItem = NSMenuItem(title: "Local only. Nothing uploaded.", action: nil, keyEquivalent: "")
        privateItem.isEnabled = false
        menu.addItem(privateItem)
        addItem("Settings…", action: #selector(showSettings), key: ",", modifiers: .command, to: menu)
        addItem("Help & Shortcuts…", action: #selector(showWelcome), to: menu)
        addItem("Screen Recording Permission…", action: #selector(openPermissions), to: menu)
        menu.addItem(.separator())
        addItem("Quit DarkShot", action: #selector(quit), key: "q", modifiers: .command, to: menu)
        statusItem.menu = menu
        shortcut.onTrigger = { [weak self] in self?.captureArea() }
        updateShortcutLabels()
        if !shortcut.register(captureCombination) {
            showError("Shortcut unavailable", message: "Another app may be using \(captureCombination.displayString). Choose another shortcut in DarkShot → Settings. You can still capture from the menu bar.")
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showWelcome()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
        // Explicit opt-in used when setting up login startup; never silently re-enable a disabled login item.
        if CommandLine.arguments.contains("--enable-launch-at-login") {
            showSettings()
            let enabled = settingsController?.setLaunchAtLoginEnabled(true) == true
            let result = enabled ? "enabled" : loginItem.status == .requiresApproval ? "requires approval" : "not enabled"
            FileHandle.standardOutput.write(Data("DarkShot launch at login: \(result)\n".utf8))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if session == nil { showWelcome() }
        return true
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        addItem("Settings…", action: #selector(showSettings), key: ",", modifiers: .command, to: appMenu)
        appMenu.addItem(.separator())
        addItem("Quit DarkShot", action: #selector(quit), key: "q", modifiers: .command, to: appMenu)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, key: String = "",
                         modifiers: NSEvent.ModifierFlags = [], to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        menu.addItem(item)
        return item
    }

    private func updateShortcutLabels() {
        statusItem.button?.toolTip = "DarkShot — Capture an area (\(captureCombination.displayString))"
        captureMenuItem?.keyEquivalent = isRecordingShortcut ? "" : captureCombination.menuKeyEquivalent
        captureMenuItem?.keyEquivalentModifierMask = captureCombination.flags
        welcomeShortcutLabel?.stringValue = "\(captureCombination.displayString)    →    drag    →    draw    →    ⌘C"
    }

    @objc private func showSettings() {
        guard session == nil, !isCapturing, !isSaving else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(
                combination: captureCombination, loginItem: loginItem,
                onApply: { [weak self] candidate in
                    guard let self else { return "DarkShot is closing." }
                    guard self.shortcut.register(candidate) else {
                        return "That shortcut is unavailable or reserved by macOS. Try another combination."
                    }
                    self.captureCombination = candidate
                    candidate.save()
                    self.updateShortcutLabels()
                    return nil
                },
                onRecordingChanged: { [weak self] recording in
                    guard let self else { return }
                    self.isRecordingShortcut = recording
                    if recording {
                        self.shortcut.suspend()
                    } else if !self.shortcut.register(self.captureCombination) {
                        self.showError("Shortcut unavailable", message: "Couldn’t restore \(self.captureCombination.displayString). Choose another shortcut in Settings.")
                    }
                    self.updateShortcutLabels()
                })
        }
        settingsController?.present()
    }

    @objc private func captureArea() {
        guard !isCapturing, !isSaving, !isRecordingShortcut else { return }
        if let session { session.close(); self.session = nil; restorePreviousApplication(); return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            let alert = NSAlert()
            alert.messageText = "Allow DarkShot to capture your screen"
            alert.informativeText = "Enable DarkShot in System Settings → Privacy & Security → Screen & System Audio Recording. macOS may ask you to quit and reopen DarkShot afterward.\n\nDarkShot captures only when you ask. It never records audio or uploads images."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { openPermissions() }
            return
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        welcomeWindow?.orderOut(nil)
        settingsController?.window?.orderOut(nil)
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                // Let the status menu / welcome window disappear before freezing the displays.
                try await Task.sleep(for: .milliseconds(90))
                let displays = try await captureService.capture()
                guard !displays.isEmpty else { throw CaptureError.noDisplays }
                let newSession = CaptureSession(displays: displays)
                newSession.onCancel = { [weak self] in self?.finishSession() }
                newSession.onExport = { [weak self] bitmap, action in self?.export(bitmap, action: action) }
                session = newSession
                newSession.show()
            } catch {
                showError("Couldn’t capture the screen", message: "\(error.localizedDescription)\n\nCheck DarkShot’s Screen Recording permission in System Settings. If you just granted access, quit and reopen the app.")
            }
        }
    }

    private func export(_ bitmap: NSBitmapImageRep, action: CaptureCanvas.ExportAction) {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            session?.hide()
            showError("Couldn’t export", message: "The image could not be encoded as PNG.")
            session?.restore()
            return
        }
        switch action {
        case .copy:
            let pasteboard = NSPasteboard.general
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            if let tiff = bitmap.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                session?.hide()
                showError("Couldn’t copy", message: "The clipboard was unavailable. Try again or save the image instead.")
                session?.restore()
                return
            }
            finishSession()
        case .save:
            isSaving = true
            session?.hide()
            let panel = NSSavePanel()
            panel.title = "Save Screenshot"
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            panel.nameFieldStringValue = "DarkShot \(formatter.string(from: Date())).png"
            if let lastDirectory = UserDefaults.standard.string(forKey: "saveDirectory") {
                panel.directoryURL = URL(fileURLWithPath: lastDirectory, isDirectory: true)
            } else {
                panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            }
            let response = panel.runModal()
            isSaving = false
            guard response == .OK, let url = panel.url else {
                session?.restore()
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "saveDirectory")
                finishSession()
            } catch {
                showError("Couldn’t save the screenshot", message: error.localizedDescription)
                session?.restore()
            }
        }
    }

    private func finishSession() {
        session?.close()
        session = nil
        restorePreviousApplication()
    }

    private func restorePreviousApplication() {
        if let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil
    }

    @objc private func showWelcome() {
        if session != nil { return }
        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 570, height: 590),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "DarkShot"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        let content = NSView()
        window.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 30)
        ])
        let mark = NSImageView(image: NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)!)
        mark.contentTintColor = .systemTeal
        mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .light)
        stack.addArrangedSubview(mark)
        stack.addArrangedSubview(label("Your screen. Just the bit you need.", size: 25, weight: .bold))
        stack.addArrangedSubview(label("Select, annotate, and get back to it.\nNative on Apple Silicon. No accounts. No uploads.", size: 14, color: .secondaryLabelColor))
        let shortcut = label("\(captureCombination.displayString)    →    drag    →    draw    →    ⌘C", size: 19, weight: .medium)
        shortcut.textColor = .systemTeal
        welcomeShortcutLabel = shortcut
        stack.addArrangedSubview(shortcut)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let capture = NSButton(title: "Capture an Area", target: self, action: #selector(captureArea))
        capture.bezelStyle = .rounded
        capture.keyEquivalent = "\r"
        let permission = NSButton(title: "Screen Recording Settings…", target: self, action: #selector(openPermissions))
        permission.bezelStyle = .rounded
        buttons.addArrangedSubview(capture)
        buttons.addArrangedSubview(permission)
        stack.addArrangedSubview(buttons)
        stack.addArrangedSubview(label("THE SHORT VERSION", size: 11, weight: .semibold, color: .secondaryLabelColor))
        stack.addArrangedSubview(label(
            "P  Pen       A  Arrow       L  Line       R  Rectangle\nO  Ellipse    H  Highlighter    T  Text    V  Move selection\n\n⌘C / Return  Copy       ⌘S  Save       Esc  Cancel\n⌘Z  Undo       ⇧⌘Z  Redo       − / +  Stroke width\nN  Reselect       Arrow keys  Nudge crop\nShift + arrows  Resize       Option  10-point steps",
            size: 13, monospaced: true))
        stack.addArrangedSubview(label("DarkShot lives in your menu bar. The first capture needs macOS Screen Recording permission. Screenshots stay in memory until you copy or save them.", size: 12, color: .secondaryLabelColor))
        welcomeWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor, monospaced: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = monospaced ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isSelectable = false
        field.preferredMaxLayoutWidth = 498
        return field
    }

    @objc private func openPermissions() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showError(_ title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func quit() {
        session?.close()
        NSApp.terminate(nil)
    }
}

private enum CaptureError: LocalizedError {
    case noDisplays
    var errorDescription: String? { "No capturable displays were found." }
}
