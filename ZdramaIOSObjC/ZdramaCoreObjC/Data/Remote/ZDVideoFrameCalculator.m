#import "ZDVideoFrameCalculator.h"

NSInteger ZDNumFramesForDuration(NSInteger durationSeconds) {
    NSInteger requested = MAX(durationSeconds, 1) * 24;
    NSInteger capped = MIN(requested, 441);
    NSInteger n = MAX(1, (capped - 1) / 8);
    return n * 8 + 1;
}
