import XCTest
@testable import Parrot

final class TranscriptTests: XCTestCase {
    func testRevisedPartialReplacesEarlierGuess() {
        var transcript = Transcript()
        transcript.receive("recognize peach", final: false)
        transcript.receive("recognize speech", final: false)
        XCTAssertEqual(transcript.text, "recognize speech")
        transcript.receive("recognize speech.", final: true)
        XCTAssertEqual(transcript.text, "recognize speech.")
        XCTAssertEqual(transcript.partial, "")
    }
    func testFinalSegmentsSurviveLaterPartialRevisions() {
        var transcript = Transcript()
        transcript.receive("Hello.", final: true)
        transcript.receive(" How", final: false)
        transcript.receive(" How are you?", final: true)
        transcript.receive(" Today", final: false)
        XCTAssertEqual(transcript.committed, "Hello. How are you?")
        XCTAssertEqual(transcript.text, "Hello. How are you? Today")
    }
}
