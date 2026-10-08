import XCTest
@testable import ZdramaCore

/// 详情页纯逻辑测试：覆盖判定、阶段中文名与生成进度。
final class ProjectDetailLogicTests: XCTestCase {
    // MARK: - 覆盖判定：text / rewrite / full

    func testTextStageConfirmsOverwriteWhenScriptExists() {
        XCTAssertTrue(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.text,
            project: makeProject(generatedScript: "第一集剧本"),
            episode: makeEpisode(),
            shots: []
        ))
        XCTAssertTrue(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.full,
            project: makeProject(),
            episode: makeEpisode(scriptContent: "改写后的剧本"),
            shots: []
        ))
        XCTAssertTrue(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.rewrite,
            project: makeProject(generatedScript: "旧脚本"),
            episode: makeEpisode(scriptContent: nil),
            shots: []
        ))
    }

    func testTextStageDoesNotConfirmOverwriteWhenScriptBlank() {
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.text,
            project: makeProject(generatedScript: nil),
            episode: makeEpisode(scriptContent: nil),
            shots: []
        ))
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.text,
            project: makeProject(generatedScript: "   \n"),
            episode: makeEpisode(scriptContent: "  "),
            shots: []
        ))
    }

    // MARK: - 覆盖判定：storyboard / image / video

    func testStoryboardStageConfirmsOverwriteWhenShotsExist() {
        XCTAssertTrue(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.storyboard,
            project: makeProject(),
            episode: makeEpisode(),
            shots: [makeShot(shotNumber: 1)]
        ))
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.storyboard,
            project: makeProject(),
            episode: makeEpisode(),
            shots: []
        ))
    }

    func testImageStageConfirmsOverwriteWhenAnyImageCompleted() {
        let shots = [
            makeShot(shotNumber: 1, imageStatus: .pending),
            makeShot(shotNumber: 2, imageStatus: .completed),
            makeShot(shotNumber: 3, imageStatus: .failed)
        ]
        XCTAssertTrue(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.image,
            project: makeProject(),
            episode: makeEpisode(),
            shots: shots
        ))
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.image,
            project: makeProject(),
            episode: makeEpisode(),
            shots: [makeShot(shotNumber: 1, imageStatus: .processing)]
        ))
    }

    func testVideoStageConfirmsOverwriteWhenAnyVideoCompleted() {
        let shots = [
            makeShot(shotNumber: 1, videoStatus: .processing),
            makeShot(shotNumber: 2, videoStatus: .completed)
        ]
        XCTAssertTrue(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.video,
            project: makeProject(),
            episode: makeEpisode(),
            shots: shots
        ))
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.video,
            project: makeProject(),
            episode: makeEpisode(),
            shots: [makeShot(shotNumber: 1, videoStatus: .pending)]
        ))
    }

    // MARK: - 覆盖判定：final_video

    func testFinalVideoStageConfirmsOverwriteOnlyWhenCompletedWithFile() {
        XCTAssertTrue(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.finalVideo,
            project: makeProject(),
            episode: makeEpisode(finalVideoStatus: .completed, finalVideoLocalPath: "/tmp/final.mp4"),
            shots: []
        ))
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.finalVideo,
            project: makeProject(),
            episode: makeEpisode(finalVideoStatus: .completed, finalVideoLocalPath: nil),
            shots: []
        ))
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.finalVideo,
            project: makeProject(),
            episode: makeEpisode(finalVideoStatus: .processing, finalVideoLocalPath: "/tmp/final.mp4"),
            shots: []
        ))
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: GenerationStageKey.finalVideo,
            project: makeProject(),
            episode: makeEpisode(finalVideoStatus: .completed, finalVideoLocalPath: "  "),
            shots: []
        ))
    }

    func testUnknownStageDoesNotConfirmOverwrite() {
        XCTAssertFalse(ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: "unknown",
            project: makeProject(generatedScript: "有脚本"),
            episode: makeEpisode(scriptContent: "有脚本"),
            shots: [makeShot(shotNumber: 1, imageStatus: .completed)]
        ))
    }

    // MARK: - 阶段中文名

    func testStageDisplayNamesAreChinese() {
        XCTAssertEqual(GenerationStage.none.displayName, "未开始")
        XCTAssertEqual(GenerationStage.text.displayName, "剧本")
        XCTAssertEqual(GenerationStage.storyboard.displayName, "分镜")
        XCTAssertEqual(GenerationStage.image.displayName, "出图")
        XCTAssertEqual(GenerationStage.video.displayName, "出视频")
        XCTAssertEqual(GenerationStage.finalVideo.displayName, "成片")
    }

    func testProjectStatusDisplayNamesAreChinese() {
        XCTAssertEqual(ProjectStatus.draft.displayName, "草稿")
        XCTAssertEqual(ProjectStatus.processing.displayName, "生成中")
        XCTAssertEqual(ProjectStatus.completed.displayName, "已完成")
        XCTAssertEqual(ProjectStatus.failed.displayName, "失败")
        XCTAssertEqual(ProjectStatus.cancelled.displayName, "已取消")
    }

    // MARK: - 进度

    func testImageProgressUsesCompletedOverTotal() {
        let shots = [
            makeShot(shotNumber: 1, imageStatus: .completed),
            makeShot(shotNumber: 2, imageStatus: .completed),
            makeShot(shotNumber: 3, imageStatus: .completed),
            makeShot(shotNumber: 4, imageStatus: .processing),
            makeShot(shotNumber: 5, imageStatus: .pending),
            makeShot(shotNumber: 6, imageStatus: .pending),
            makeShot(shotNumber: 7, imageStatus: .pending),
            makeShot(shotNumber: 8, imageStatus: .pending)
        ]
        let progress = ProjectGenerationLogic.progress(stage: .image, shots: shots)
        XCTAssertEqual(progress.completedCount, 3)
        XCTAssertEqual(progress.totalCount, 8)
        XCTAssertEqual(progress.processingShotNumber, 4)
        XCTAssertEqual(progress.fraction, 3.0 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(progress.displayText, "出图 3/8")
    }

    func testVideoProgressUsesCompletedOverTotal() {
        let shots = [
            makeShot(shotNumber: 1, videoStatus: .completed),
            makeShot(shotNumber: 2, videoStatus: .completed),
            makeShot(shotNumber: 3, videoStatus: .completed),
            makeShot(shotNumber: 4, videoStatus: .completed),
            makeShot(shotNumber: 5, videoStatus: .completed),
            makeShot(shotNumber: 6, videoStatus: .pending),
            makeShot(shotNumber: 7, videoStatus: .pending),
            makeShot(shotNumber: 8, videoStatus: .pending)
        ]
        let progress = ProjectGenerationLogic.progress(stage: .video, shots: shots)
        XCTAssertEqual(progress.completedCount, 5)
        XCTAssertEqual(progress.totalCount, 8)
        XCTAssertNil(progress.processingShotNumber)
        XCTAssertEqual(progress.displayText, "出视频 5/8")
    }

    func testNonMediaStageProgressText() {
        let progress = ProjectGenerationLogic.progress(stage: .storyboard, shots: [])
        XCTAssertEqual(progress.displayText, "正在生成分镜…")
        XCTAssertEqual(progress.fraction, 0)
    }

    func testFinalVideoProgressText() {
        let progress = ProjectGenerationLogic.progress(stage: .finalVideo, shots: [])
        XCTAssertEqual(progress.displayText, "正在合成成片…")
    }

    // MARK: - 辅助构造

    private func makeProject(generatedScript: String? = nil) -> DramaProject {
        DramaProject(
            id: 1,
            title: "测试项目",
            prompt: "提示词",
            style: "现代短剧",
            targetAudience: "大众受众",
            aspectRatio: "9:16",
            shotCount: 8,
            shotDurationSeconds: 5,
            status: .draft,
            currentStage: .none,
            errorMessage: nil,
            generatedScript: generatedScript,
            finalVideoStatus: .pending,
            finalVideoLocalPath: nil,
            finalVideoErrorMessage: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }

    private func makeEpisode(
        scriptContent: String? = nil,
        finalVideoStatus: AssetStatus = .pending,
        finalVideoLocalPath: String? = nil
    ) -> Episode {
        Episode(
            id: 1,
            projectId: 1,
            episodeNumber: 1,
            title: "第一集",
            content: "原始内容",
            scriptContent: scriptContent,
            status: .draft,
            finalVideoStatus: finalVideoStatus,
            finalVideoLocalPath: finalVideoLocalPath,
            finalVideoErrorMessage: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }

    private func makeShot(
        shotNumber: Int,
        imageStatus: AssetStatus = .pending,
        videoStatus: AssetStatus = .pending
    ) -> StoryboardShot {
        StoryboardShot(
            id: Int64(shotNumber),
            projectId: 1,
            episodeId: 1,
            shotNumber: shotNumber,
            scene: "",
            action: "",
            dialogue: "",
            camera: "",
            imagePrompt: "",
            videoPrompt: "",
            durationSeconds: 5,
            characterNames: [],
            characterIds: nil,
            imageStatus: imageStatus,
            imageUrl: nil,
            imageLocalPath: nil,
            imageErrorMessage: nil,
            videoStatus: videoStatus,
            videoTaskId: nil,
            videoUrl: nil,
            videoLocalPath: nil,
            videoErrorMessage: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }
}
