import XCTest
@testable import ZdramaCore

final class DramaModelsTests: XCTestCase {
    func testPersistedEnumRawValuesMatchAndroid() {
        XCTAssertEqual(ProjectStatus.draft.rawValue, "DRAFT")
        XCTAssertEqual(ProjectStatus.processing.rawValue, "PROCESSING")
        XCTAssertEqual(ProjectStatus.completed.rawValue, "COMPLETED")
        XCTAssertEqual(ProjectStatus.failed.rawValue, "FAILED")
        XCTAssertEqual(ProjectStatus.cancelled.rawValue, "CANCELLED")
        XCTAssertEqual(GenerationStage.none.rawValue, "NONE")
        XCTAssertEqual(GenerationStage.text.rawValue, "TEXT")
        XCTAssertEqual(GenerationStage.storyboard.rawValue, "STORYBOARD")
        XCTAssertEqual(GenerationStage.image.rawValue, "IMAGE")
        XCTAssertEqual(GenerationStage.video.rawValue, "VIDEO")
        XCTAssertEqual(GenerationStage.finalVideo.rawValue, "FINAL_VIDEO")
        XCTAssertEqual(AssetStatus.pending.rawValue, "PENDING")
        XCTAssertEqual(EpisodeStatus.rewriting.rawValue, "REWRITING")
    }

    func testUnknownPersistedValuesFallBack() {
        XCTAssertEqual(ProjectStatus(persisted: "nope"), .draft)
        XCTAssertEqual(GenerationStage(persisted: nil), .none)
        XCTAssertEqual(AssetStatus(persisted: ""), .pending)
        XCTAssertEqual(EpisodeStatus(persisted: "X"), .draft)
    }
}
