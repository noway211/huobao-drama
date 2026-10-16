#import "ZDLocalMp4Composer.h"
#import <AVFoundation/AVFoundation.h>

static NSError *ZDComposeError(NSString *message) {
    return [NSError errorWithDomain:@"ZDLocalMp4Composer" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

BOOL ZDValidateComposeInputs(NSArray<NSString *> *paths, NSError **error) {
    if (paths.count == 0) {
        if (error) *error = ZDComposeError(@"请先生成并下载全部分镜视频后再合成成片");
        return NO;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    NSUInteger index = 1;
    for (NSString *path in paths) {
        if (![files fileExistsAtPath:path]) {
            if (error) *error = ZDComposeError([NSString stringWithFormat:@"分镜 #%lu 的本地视频不存在，请重新生成视频", (unsigned long)index]);
            return NO;
        }
        index += 1;
    }
    return YES;
}

static NSString *ZDFourCC(FourCharCode code) {
    char bytes[5] = {
        (char)((code >> 24) & 0xFF),
        (char)((code >> 16) & 0xFF),
        (char)((code >> 8) & 0xFF),
        (char)(code & 0xFF),
        0
    };
    NSString *text = [[NSString alloc] initWithBytes:bytes length:4 encoding:NSASCIIStringEncoding];
    return text ?: [NSString stringWithFormat:@"%u", code];
}

static NSInteger ZDRotationDegrees(CGAffineTransform transform) {
    NSInteger degrees = (NSInteger)llround(atan2(transform.b, transform.a) * 180.0 / M_PI);
    NSInteger normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
}

@implementation ZDLocalMp4Composer

- (BOOL)composePaths:(NSArray<NSString *> *)paths toURL:(NSURL *)output error:(NSError **)error {
    if (!ZDValidateComposeInputs(paths, error)) return NO;

    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    if (!videoTrack) {
        if (error) *error = ZDComposeError(@"成片 MP4 写入失败，请重试");
        return NO;
    }
    AVMutableCompositionTrack *audioTrack = nil;
    CMTime cursor = kCMTimeZero;
    NSDictionary *reference = nil;

    for (NSString *path in paths) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        AVAssetTrack *sourceVideo = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        if (!sourceVideo) {
            if (error) *error = ZDComposeError(@"分镜视频缺少视频轨，无法合成 MP4");
            return NO;
        }
        NSDictionary *spec = [self specForVideo:sourceVideo asset:asset];
        if (reference && ![self spec:spec matches:reference]) {
            if (error) *error = ZDComposeError(@"分镜视频参数不一致，无法在本机无转码合成 MP4");
            [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
            return NO;
        }
        if (!reference) reference = spec;

        CMTimeRange range = CMTimeRangeMake(kCMTimeZero, asset.duration);
        NSError *insertError = nil;
        if (![videoTrack insertTimeRange:range ofTrack:sourceVideo atTime:cursor error:&insertError]) {
            if (error) *error = ZDComposeError(@"成片 MP4 写入失败，请重试");
            [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
            return NO;
        }
        if (CMTIME_COMPARE_INLINE(cursor, ==, kCMTimeZero)) {
            videoTrack.preferredTransform = sourceVideo.preferredTransform;
        }
        AVAssetTrack *sourceAudio = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
        if (sourceAudio) {
            if (!audioTrack) {
                audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
            }
            if (!audioTrack || ![audioTrack insertTimeRange:range ofTrack:sourceAudio atTime:cursor error:&insertError]) {
                if (error) *error = ZDComposeError(@"成片 MP4 写入失败，请重试");
                [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
                return NO;
            }
        }
        cursor = CMTimeAdd(cursor, asset.duration);
    }

    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:[output URLByDeletingLastPathComponent]
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&directoryError];
    if (directoryError) {
        if (error) *error = ZDComposeError(@"成片 MP4 写入失败，请重试");
        return NO;
    }
    [[NSFileManager defaultManager] removeItemAtURL:output error:nil];

    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    __block NSError *exportError = nil;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    if (!session) {
        if (error) *error = ZDComposeError(@"成片 MP4 写入失败，请重试");
        return NO;
    }
    session.outputURL = output;
    session.outputFileType = AVFileTypeMPEG4;
    [session exportAsynchronouslyWithCompletionHandler:^{
        if (session.status != AVAssetExportSessionStatusCompleted) {
            exportError = ZDComposeError(@"成片 MP4 写入失败，请重试");
            [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
        }
        dispatch_semaphore_signal(gate);
    }];
    dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
    if (exportError) {
        if (error) *error = exportError;
        return NO;
    }
    return YES;
}

- (NSDictionary *)specForVideo:(AVAssetTrack *)video asset:(AVAsset *)asset {
    CMFormatDescriptionRef videoFormat = (__bridge CMFormatDescriptionRef)video.formatDescriptions.firstObject;
    NSString *videoMIME = videoFormat ? [NSString stringWithFormat:@"video/%@", ZDFourCC(CMFormatDescriptionGetMediaSubType(videoFormat))] : @"video/mp4";
    AVAssetTrack *audio = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    NSString *audioMIME = @"";
    NSInteger sampleRate = 0;
    NSInteger channels = 0;
    if (audio) {
        CMFormatDescriptionRef audioFormat = (__bridge CMFormatDescriptionRef)audio.formatDescriptions.firstObject;
        if (audioFormat) {
            audioMIME = [NSString stringWithFormat:@"audio/%@", ZDFourCC(CMFormatDescriptionGetMediaSubType(audioFormat))];
            const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat);
            if (asbd) {
                sampleRate = (NSInteger)asbd->mSampleRate;
                channels = (NSInteger)asbd->mChannelsPerFrame;
            }
        }
    }
    return @{
        @"video": videoMIME,
        @"width": @((NSInteger)llround(video.naturalSize.width)),
        @"height": @((NSInteger)llround(video.naturalSize.height)),
        @"rotation": @(ZDRotationDegrees(video.preferredTransform)),
        @"audio": audioMIME,
        @"rate": @(sampleRate),
        @"channels": @(channels)
    };
}

- (BOOL)spec:(NSDictionary *)candidate matches:(NSDictionary *)reference {
    if (![candidate[@"video"] isEqual:reference[@"video"]] ||
        ![candidate[@"width"] isEqual:reference[@"width"]] ||
        ![candidate[@"height"] isEqual:reference[@"height"]] ||
        ![candidate[@"rotation"] isEqual:reference[@"rotation"]]) {
        return NO;
    }
    BOOL referenceSilent = [reference[@"audio"] length] == 0 && [reference[@"rate"] integerValue] == 0 && [reference[@"channels"] integerValue] == 0;
    BOOL candidateSilent = [candidate[@"audio"] length] == 0 && [candidate[@"rate"] integerValue] == 0 && [candidate[@"channels"] integerValue] == 0;
    if (referenceSilent && candidateSilent) return YES;
    if ([reference[@"audio"] length] == 0 || [candidate[@"audio"] length] == 0) return NO;
    return [candidate[@"audio"] isEqual:reference[@"audio"]] &&
        [candidate[@"rate"] isEqual:reference[@"rate"]] &&
        [candidate[@"channels"] isEqual:reference[@"channels"]];
}

@end
