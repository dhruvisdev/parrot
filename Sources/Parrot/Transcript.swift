import Foundation

struct Transcript {
    private(set) var committed = ""
    private(set) var partial = ""
    var text: String { committed + partial }
    mutating func receive(_ text: String, final: Bool) {
        if final { committed += text; partial = "" }
        else { partial = text }
    }
}

enum ParrotError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
