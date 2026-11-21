import AppKit
import Carbon

@main
struct ShortcutChecks {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        var checks = 0
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            checks += 1
            if !condition { failures += 1 }
            print("\(condition ? "PASS" : "FAIL") \(name)")
        }
        func key(_ text: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: 0, context: nil, characters: text,
                             charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        }
        let domain = "com.darkshot.checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        check("default shortcut is Control-Option-D", ShortcutCombination.default.displayString == "⌃⌥D")
        check("empty preferences use default", ShortcutCombination.load(from: defaults) == .default)
        let custom = ShortcutCombination(event: key("5", code: UInt16(kVK_ANSI_5), flags: [.command, .shift]))
        check("custom combination validates", custom.validationMessage == nil)
        check("modifier display order", custom.displayString == "⇧⌘5")
        check("Carbon modifier mapping", custom.carbonModifiers == UInt32(shiftKey | cmdKey))
        custom.save(to: defaults)
        check("custom shortcut persists", ShortcutCombination.load(from: defaults) == custom)
        check("plain letter rejected", ShortcutCombination(event: key("d", code: 2)).validationMessage != nil)
        check("Shift alone rejected", ShortcutCombination(event: key("D", code: 2, flags: .shift)).validationMessage != nil)
        let f13 = ShortcutCombination(event: key("", code: UInt16(kVK_F13)))
        check("unmodified F13 supported", f13.validationMessage == nil && f13.displayString == "F13")
        check("F13 menu equivalent", f13.menuKeyEquivalent == "\u{f710}")
        let space = ShortcutCombination(event: key(" ", code: UInt16(kVK_Space), flags: .option))
        check("special keys have readable names", space.displayString == "⌥Space" && space.menuKeyEquivalent == " ")
        let filtered = ShortcutCombination(event: key("D", code: 2, flags: [.control, .option, .capsLock, .function]))
        check("irrelevant modifier flags removed", filtered == .default)
        defaults.set(Data("not-json".utf8), forKey: "captureShortcut")
        check("corrupt preferences fall back safely", ShortcutCombination.load(from: defaults) == .default)
        let invalid = ShortcutCombination(keyCode: 65535, flags: .command, keyLabel: "Bad")
        invalid.save(to: defaults)
        check("invalid saved key falls back safely", ShortcutCombination.load(from: defaults) == .default)

        var attempted: ShortcutCombination?
        var failureMessage: String?
        var recordingStates: [Bool] = []
        let settings = SettingsWindowController(combination: .default, loginItem: LaunchAtLogin(),
            onApply: { candidate in
                attempted = candidate
                return failureMessage
            },
            onRecordingChanged: { recordingStates.append($0) })
        let recorder = settings.recorder
        recorder.beginRecording()
        check("recording starts and suspends hotkey", recorder.isRecording && recordingStates == [true])
        recorder.keyDown(with: key("j", code: UInt16(kVK_ANSI_J)))
        check("invalid recording stays open", recorder.isRecording && attempted == nil)
        failureMessage = "Already in use."
        _ = recorder.performKeyEquivalent(with: key("5", code: UInt16(kVK_ANSI_5), flags: [.command, .shift]))
        check("conflict keeps old shortcut", recorder.combination == .default && recorder.isRecording)
        failureMessage = nil
        let handled = settings.window!.performKeyEquivalent(with: key("5", code: UInt16(kVK_ANSI_5), flags: [.command, .shift]))
        check("window routes Command combination to recorder", handled && attempted == custom)
        check("successful recording updates shortcut", recorder.combination == custom && !recorder.isRecording)
        check("successful recording restores hotkey", recordingStates == [true, false])
        recorder.beginRecording()
        recorder.keyDown(with: key("", code: UInt16(kVK_Escape)))
        check("Escape cancels recording without changing shortcut", !recorder.isRecording && recorder.combination == custom)
        recorder.beginRecording()
        settings.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        check("leaving Settings cancels recording", !recorder.isRecording && recordingStates.last == false)
        recorder.beginRecording()
        recorder.keyDown(with: key("", code: UInt16(kVK_F13)))
        check("F-key can be recorded", recorder.combination == f13 && !recorder.isRecording)
        recorder.beginRecording()
        settings.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        check("closing Settings restores hotkey", !recorder.isRecording && recordingStates.last == false)

        let content = settings.window!.contentView!
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: ".build/checks/settings-preview.png"))
            }
            check("Settings UI renders", bitmap.pixelsWide > 0)
        } else { check("Settings UI renders", false) }
        settings.window?.close()
        print("\(checks - failures)/\(checks) shortcut/settings checks passed")
        exit(failures == 0 ? 0 : 1)
    }
}
