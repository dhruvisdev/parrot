import AppKit
import Carbon

final class Hotkey {
    private var reference: EventHotKeyRef?
    private var escape: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?
    private var held = false

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            if id.id == 2 {
                if pressed { owner.onEscape?() }
            } else if pressed {
                if !owner.held { owner.held = true; owner.onPress?() }
            } else { owner.held = false; owner.onRelease?() }
            return noErr
        }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) throws {
        unregister()
        let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x50525254, id: 1), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { throw ParrotError.message("\(shortcut.display) is already in use. Choose another shortcut.") }
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        held = false
    }
    /// Escape is claimed only while the orb is visible, so other apps keep it otherwise.
    func captureEscape(_ enabled: Bool) {
        if enabled, escape == nil {
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x50525254, id: 2), GetApplicationEventTarget(), 0, &escape)
        } else if !enabled, let escape {
            UnregisterEventHotKey(escape); self.escape = nil
        }
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let escape { UnregisterEventHotKey(escape) }
        if let handler { RemoveEventHandler(handler) }
    }
}
