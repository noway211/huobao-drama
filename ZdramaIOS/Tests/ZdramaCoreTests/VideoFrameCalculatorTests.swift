import XCTest
@testable import ZdramaCore

final class VideoFrameCalculatorTests: XCTestCase {
    func testNumFramesForOneSecondIs17() {
        XCTAssertEqual(VideoFrameCalculator.numFrames(durationSeconds: 1), 17)
    }

    func testNumFramesForZeroSecondsIs17() {
        XCTAssertEqual(VideoFrameCalculator.numFrames(durationSeconds: 0), 17)
    }

    func testNumFramesFor100SecondsIsCappedAt441() {
        XCTAssertEqual(VideoFrameCalculator.numFrames(durationSeconds: 100), 441)
    }
}
