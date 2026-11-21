import Carbon

/// Carbon's hot-key API registers a shortcut without monitoring keystrokes or needing Accessibility access.
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registeredCombination: ShortcutCombination?
    var onTrigger: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.onTrigger?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult
    func register(_ combination: ShortcutCombination = .default) -> Bool {
        guard combination.validationMessage == nil else { return false }
        if hotKey != nil, registeredCombination == combination { return true }
        let id = EventHotKeyID(signature: 0x44534854, id: 1)
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(UInt32(combination.keyCode), combination.carbonModifiers,
                                  id, GetApplicationEventTarget(), 0, &replacement) == noErr else { return false }
        // Keep the old shortcut if registering its replacement fails.
        suspend()
        hotKey = replacement
        registeredCombination = combination
        return true
    }

    func suspend() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
