import XCTest
@testable import ZdramaCore

final class ChatResponseTextExtractorTests: XCTestCase {
    func testExtractsStringContent() throws {
        let json: [String: Any] = [
            "choices": [["message": ["content": "hello script"], "finish_reason": "stop"]]
        ]
        XCTAssertEqual(ChatResponseTextExtractor.extract(json), "hello script")
        XCTAssertEqual(ChatResponseTextExtractor.finishReason(json), "stop")
    }

    func testExtractsContentPartsArray() {
        let json: [String: Any] = [
            "choices": [["message": ["content": [["type": "text", "text": "part-a"], ["text": "part-b"]]]]]
        ]
        XCTAssertEqual(ChatResponseTextExtractor.extractFinalContent(json), "part-a\npart-b")
    }

    func testExtractFallsBackToReasoningContent() {
        let json: [String: Any] = [
            "choices": [["message": ["content": "", "reasoning_content": "hidden"]]]
        ]
        XCTAssertEqual(ChatResponseTextExtractor.extractFinalContent(json), "")
        XCTAssertEqual(ChatResponseTextExtractor.extract(json), "hidden")
    }

    func testOutputTextWins() {
        let json: [String: Any] = ["output_text": "from-output"]
        XCTAssertEqual(ChatResponseTextExtractor.extractFinalContent(json), "from-output")
    }
}
