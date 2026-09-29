import XCTest
@testable import ZdramaCore

final class GenerationPreflightTests: XCTestCase {
    func testImageStageWithEmptyApiKeyThrowsMissingApiKey() {
        let input = makeInput(apiKey: "")
        XCTAssertThrowsError(try GenerationPreflight.check(stage: "image", input: input)) { error in
            XCTAssertEqual(error as? PreflightError, .missingApiKey)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "Agnes API Key is required")
        }
    }

    func testFinalVideoIgnoresEmptyApiKeyAndRequiresLocalVideos() {
        let input = makeInput(
            apiKey: "",
            shots: [makeShot(videoLocalPath: nil)]
        )
        XCTAssertThrowsError(try GenerationPreflight.check(stage: "final_video", input: input)) { error in
            XCTAssertEqual(error as? PreflightError, .missingLocalVideos)
            XCTAssertNotEqual(error as? PreflightError, .missingApiKey)
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "请先生成并下载全部分镜视频后再合成成片"
            )
        }
    }

    func testRewriteWithNilContentThrowsMissingRawContent() {
        let input = makeInput(episodeContent: nil)
        XCTAssertThrowsError(try GenerationPreflight.check(stage: "rewrite", input: input)) { error in
            XCTAssertEqual(error as? PreflightError, .missingRawContent)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "请先为本集创作或改写脚本")
        }
    }

    func testVideoPassesWhenImageUrlPresentEvenIfLocalPathNil() {
        let input = makeInput(
            shots: [makeShot(imageUrl: "https://example.com/shot.png", imageLocalPath: nil)]
        )
        XCTAssertNoThrow(try GenerationPreflight.check(stage: "video", input: input))
    }

    private func makeInput(
        apiKey: String = "test-key",
        episodeContent: String? = "raw episode",
        scriptContent: String? = "script",
        shots: [StoryboardShot] = [],
        existingFiles: Set<String> = []
    ) -> PreflightInput {
        PreflightInput(
            apiKey: apiKey,
            episodeContent: episodeContent,
            scriptContent: scriptContent,
            shots: shots,
            fileExists: { existingFiles.contains($0) }
        )
    }

    private func makeShot(
        imageUrl: String? = nil,
        imageLocalPath: String? = nil,
        videoLocalPath: String? = nil
    ) -> StoryboardShot {
        StoryboardShot(
            id: 1,
            projectId: 1,
            episodeId: nil,
            shotNumber: 1,
            scene: "",
            action: "",
            dialogue: "",
            camera: "",
            imagePrompt: "",
            videoPrompt: "",
            durationSeconds: 5,
            characterNames: [],
            characterIds: nil,
            imageStatus: .pending,
            imageUrl: imageUrl,
            imageLocalPath: imageLocalPath,
            imageErrorMessage: nil,
            videoStatus: .pending,
            videoTaskId: nil,
            videoUrl: nil,
            videoLocalPath: videoLocalPath,
            videoErrorMessage: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }
}
