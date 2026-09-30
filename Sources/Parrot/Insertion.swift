import AppKit
import ApplicationServices
import Carbon

struct InsertionTarget {
    let pid: pid_t
    let element: AXUIElement?
    static func capture() -> Self? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var value: CFTypeRef?
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &value)
        let element = value.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        return Self(pid: app.processIdentifier, element: element)
    }
    func isStillFocused() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        // Chromium, Electron, and many terminals expose no focused element; the app match is all that can be checked.
        guard let element, let current = Self.capture()?.element else { return true }
        return CFEqual(element, current)
    }
}

@MainActor enum Inserter {
    static func insert(_ text: String, into target: InsertionTarget?) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "No speech detected" }
        guard let target, target.isStillFocused() else { copy(text); return "Copied — focus changed" }
        guard !IsSecureEventInputEnabled() else { copy(text); return "Copied — this field is protected" }
        if let element = target.element, setSelectedText(text, in: element) { return nil }
        return paste(text) ? nil : "Copied — paste into your text field"
    }

    /// Some apps (Chromium, Electron) report success without inserting, so only a visible change counts.
    private static func setSelectedText(_ text: String, in element: AXUIElement) -> Bool {
        var writable = DarwinBoolean(false)
        guard let before = value(of: element),
              AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success, writable.boolValue,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return false }
        return value(of: element) != before
    }
    private static func value(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Pastes with Command–V, then restores the previous clipboard unless something else has changed it since.
    private static func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        copy(text)
        let change = pasteboard.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        guard !saved.isEmpty else { return true }
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard pasteboard.changeCount == change else { return }
            pasteboard.clearContents(); pasteboard.writeObjects(saved)
        }
        return true
    }
    /// Marked transient so clipboard managers do not keep dictated text.
    private static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
    }
}
