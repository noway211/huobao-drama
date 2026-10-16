#import "ZDGenerationPreflight.h"

static BOOL ZDBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSError *ZDPreflightError(NSString *message) {
    return [NSError errorWithDomain:@"ZDGenerationPreflight" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSError *ZDPreflightStage(NSString *stage,
                          NSString *apiKey,
                          NSString *episodeContent,
                          NSString *scriptContent,
                          NSArray<ZDStoryboardShot *> *shots,
                          ZDFileExistsBlock fileExists) {
    if (![stage isEqualToString:@"final_video"] && ZDBlank(apiKey)) {
        return ZDPreflightError(@"Agnes API Key is required");
    }
    if ([stage isEqualToString:@"rewrite"] && ZDBlank(episodeContent)) {
        return ZDPreflightError(@"请先为本集创作或改写脚本");
    }
    if ([stage isEqualToString:@"storyboard"] && ZDBlank(scriptContent)) {
        return ZDPreflightError(@"请先为本集创作或改写脚本");
    }
    if ([stage isEqualToString:@"image"] || [stage isEqualToString:@"video"] || [stage isEqualToString:@"final_video"]) {
        if (shots.count == 0) return ZDPreflightError(@"请先生成分镜");
    }
    if ([stage isEqualToString:@"video"]) {
        for (ZDStoryboardShot *shot in shots) {
            BOOL hasFile = shot.imageLocalPath.length > 0 && fileExists(shot.imageLocalPath);
            if (!hasFile && ZDBlank(shot.imageUrl)) return ZDPreflightError(@"请先生成分镜图");
        }
    }
    if ([stage isEqualToString:@"final_video"]) {
        for (ZDStoryboardShot *shot in shots) {
            if (shot.videoLocalPath.length == 0 || !fileExists(shot.videoLocalPath)) {
                return ZDPreflightError(@"请先生成并下载全部分镜视频后再合成成片");
            }
        }
    }
    return nil;
}
