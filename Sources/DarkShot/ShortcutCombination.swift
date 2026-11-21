import AppKit
import Carbon

struct ShortcutCombination: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt
    let keyLabel: String

    static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let `default` = ShortcutCombination(keyCode: UInt16(kVK_ANSI_D),
                                               flags: [.control, .option], keyLabel: "D")
    private static let preferenceKey = "captureShortcut"
    private static let functionKeyCodes = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]
    private static let specialKeys: [Int: (label: String, equivalent: String)] = [
        kVK_Space: ("Space", " "), kVK_Return: ("↩", "\r"), kVK_Tab: ("⇥", "\t"),
        kVK_Delete: ("⌫", "\u{8}"), kVK_ForwardDelete: ("⌦", "\u{7f}"),
        kVK_Escape: ("⎋", "\u{1b}"), kVK_LeftArrow: ("←", "\u{f702}"),
        kVK_RightArrow: ("→", "\u{f703}"), kVK_UpArrow: ("↑", "\u{f700}"),
        kVK_DownArrow: ("↓", "\u{f701}"), kVK_Home: ("↖", "\u{f729}"),
        kVK_End: ("↘", "\u{f72b}"), kVK_PageUp: ("⇞", "\u{f72c}"),
        kVK_PageDown: ("⇟", "\u{f72d}")
    ]

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        modifiers = flags.intersection(Self.supportedModifiers).rawValue
        self.keyLabel = keyLabel
    }

    init(event: NSEvent) {
        let code = Int(event.keyCode)
        let label: String
        if let index = Self.functionKeyCodes.firstIndex(of: code) {
            label = "F\(index + 1)"
        } else if let special = Self.specialKeys[code] {
            label = special.label
        } else {
            label = (event.charactersIgnoringModifiers ?? "").uppercased()
        }
        self.init(keyCode: event.keyCode, flags: event.modifierFlags, keyLabel: label)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var validationMessage: String? {
        guard keyCode <= 127, ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(Int(keyCode)),
              !keyLabel.isEmpty, keyLabel.count <= 24,
              modifiers == flags.intersection(Self.supportedModifiers).rawValue else {
            return "That key can’t be used as a shortcut."
        }
        guard !flags.intersection([.control, .option, .command]).isEmpty ||
                Self.functionKeyCodes.contains(Int(keyCode)) else {
            return "Include Control, Option, or Command, or use an F-key on its own."
        }
        return nil
    }

    var displayString: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyLabel
    }

    var menuKeyEquivalent: String {
        if let index = Self.functionKeyCodes.firstIndex(of: Int(keyCode)) {
            return String(UnicodeScalar(0xf704 + index)!)
        }
        return Self.specialKeys[Int(keyCode)]?.equivalent ?? keyLabel.lowercased()
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.preferenceKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: preferenceKey),
              let shortcut = try? JSONDecoder().decode(Self.self, from: data),
              shortcut.validationMessage == nil else { return .default }
        return shortcut
    }
}
