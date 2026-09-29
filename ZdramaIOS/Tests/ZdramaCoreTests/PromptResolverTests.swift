import XCTest
@testable import ZdramaCore

final class PromptResolverTests: XCTestCase {
    func testBlankCustomFallsBack() {
        XCTAssertEqual(PromptResolver.resolve(custom: nil, default: "D"), "D")
        XCTAssertEqual(PromptResolver.resolve(custom: "  ", default: "D"), "D")
        XCTAssertEqual(PromptResolver.resolve(custom: " mine ", default: "D"), "mine")
    }

    func testDefaultsContainSceneHeaderRule() {
        XCTAssertTrue(PromptDefaults.scriptCreatePrompt.contains("## S编号"))
        XCTAssertTrue(PromptDefaults.storyboardPrompt.contains("image_prompt"))
        XCTAssertTrue(PromptDefaults.characterExtractPrompt.contains("主角/配角/龙套"))
    }
}
