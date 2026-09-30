import AppKit
import Carbon

struct Shortcut: Equatable {
    var key: UInt32
    var modifiers: UInt32
    var name: String
    static let standard = Shortcut(key: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), name: "Space")

    static func load() -> Shortcut {
        let defaults = UserDefaults.standard
        if let key = defaults.object(forKey: "shortcutKey") as? Int {
            return Shortcut(key: UInt32(key), modifiers: UInt32(defaults.integer(forKey: "shortcutModifiers")),
                            name: defaults.string(forKey: "shortcutName") ?? "Key \(key)")
        }
        // Earlier versions stored only a key code and always used Control–Option.
        if let legacy = defaults.object(forKey: "shortcut") as? Int {
            return Shortcut(key: UInt32(legacy), modifiers: standard.modifiers, name: legacy == kVK_Space ? "Space" : legacy == kVK_ANSI_D ? "D" : "F")
        }
        return .standard
    }
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(key), forKey: "shortcutKey")
        defaults.set(Int(modifiers), forKey: "shortcutModifiers")
        defaults.set(name, forKey: "shortcutName")
        defaults.removeObject(forKey: "shortcut")
    }

    /// Rejects bare or Shift-only letters, which would hijack ordinary typing; function keys may stand alone.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        let code = Int(event.keyCode)
        let function = Self.functionKeys[code] != nil
        guard code != kVK_Escape, function || modifiers & ~shiftKey != 0 else { return nil }
        let name = Self.functionKeys[code] ?? Self.specialKeys[code] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(key: UInt32(code), modifiers: UInt32(modifiers), name: name)
    }
    init(key: UInt32, modifiers: UInt32, name: String) { self.key = key; self.modifiers = modifiers; self.name = name }

    var display: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols.isEmpty ? name : symbols + " " + name
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
    ]
}
