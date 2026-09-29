import XCTest
@testable import ZdramaCore

final class StoryboardJSONParserTests: XCTestCase {
    func testParsesJSONArrayWrappedInMarkdownFence() throws {
        let content = """
        Here is the storyboard:
        ```json
        [
          {
            "shot_number": "1",
            "scene": "内景",
            "action": "走进房间",
            "dialogue": "你好",
            "camera": "中景",
            "image_prompt": "a room",
            "video_prompt": "walk in",
            "duration_seconds": "5",
            "character_names": ["Alice"]
          }
        ]
        ```
        """

        let items = try StoryboardJSONParser.parse(content)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].shotNumber, "1")
        XCTAssertEqual(items[0].scene, "内景")
        XCTAssertEqual(items[0].action, "走进房间")
        XCTAssertEqual(items[0].dialogue, "你好")
        XCTAssertEqual(items[0].camera, "中景")
        XCTAssertEqual(items[0].imagePrompt, "a room")
        XCTAssertEqual(items[0].videoPrompt, "walk in")
        XCTAssertEqual(items[0].durationSeconds, "5")
        XCTAssertEqual(items[0].characterNames, ["Alice"])
    }

    func testMissingJSONArrayThrowsNotJSON() {
        XCTAssertThrowsError(try StoryboardJSONParser.parse("this is not an array")) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("not JSON"),
                "expected localizedDescription to contain 'not JSON', got: \(error.localizedDescription)"
            )
        }
    }

    func testCountSceneHeadersMatchesS01AndS02() {
        let script = """
        ## S01 | 内景
        对白若干
        ## S02 | 外景
        动作若干
        """
        XCTAssertEqual(StoryboardJSONParser.countSceneHeaders(script), 2)
    }
}
