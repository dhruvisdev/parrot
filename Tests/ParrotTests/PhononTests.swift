import XCTest
@testable import Parrot

final class PhononTests: XCTestCase {
    func testParsesServerEvents() {
        XCTAssertEqual(PhononEvent(json: Data(#"{"type":"partial","text":"Hello"}"#.utf8)), .partial("Hello"))
        XCTAssertEqual(PhononEvent(json: Data(#"{"type":"final","text":"Hello.","segment":1}"#.utf8)), .final("Hello."))
        XCTAssertEqual(PhononEvent(json: Data(#"{"type":"done","text":"Hello."}"#.utf8)), .done("Hello."))
        XCTAssertEqual(PhononEvent(json: Data(#"{"type":"error","message":"busy"}"#.utf8)), .error("busy"))
        XCTAssertNil(PhononEvent(json: Data(#"{"type":"ping"}"#.utf8)))
        XCTAssertNil(PhononEvent(json: Data("not json".utf8)))
    }
    func testPhrasesJoinWithSpacesAndPartialReplacesItself() {
        var transcript = PhraseTranscript()
        transcript.receive(.partial("Hello the"))
        transcript.receive(.partial("Hello there."))
        XCTAssertEqual(transcript.text, "Hello there.")
        transcript.receive(.final("Hello there."))
        transcript.receive(.partial("How are"))
        XCTAssertEqual(transcript.text, "Hello there. How are")
        transcript.receive(.final("How are you?"))
        XCTAssertEqual(transcript.text, "Hello there. How are you?")
        XCTAssertEqual(transcript.partial, "")
    }
}
