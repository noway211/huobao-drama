import Foundation

public enum VideoFrameCalculator {
    public static let frameRate = 24
    public static let maxNumFrames = 441

    public static func numFrames(durationSeconds: Int) -> Int {
        let requested = max(durationSeconds, 1) * frameRate
        let capped = min(requested, maxNumFrames)
        let n = max(1, (capped - 1) / 8)
        return n * 8 + 1
    }
}
