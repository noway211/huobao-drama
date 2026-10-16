#import "ZDDramaModels.h"

static NSString *ZDStringFromSet(NSString *value, NSSet<NSString *> *allowed, NSString *fallback) {
    if (value != nil && [allowed containsObject:value]) {
        return value;
    }
    return fallback;
}

NSString *ZDProjectStatusFromPersisted(NSString *value) {
    return ZDStringFromSet(value, [NSSet setWithObjects:@"DRAFT", @"PROCESSING", @"COMPLETED", @"FAILED", @"CANCELLED", nil], @"DRAFT");
}

NSString *ZDGenerationStageFromPersisted(NSString *value) {
    return ZDStringFromSet(value, [NSSet setWithObjects:@"NONE", @"TEXT", @"STORYBOARD", @"IMAGE", @"VIDEO", @"FINAL_VIDEO", nil], @"NONE");
}

NSString *ZDAssetStatusFromPersisted(NSString *value) {
    return ZDStringFromSet(value, [NSSet setWithObjects:@"PENDING", @"PROCESSING", @"COMPLETED", @"FAILED", nil], @"PENDING");
}

NSString *ZDEpisodeStatusFromPersisted(NSString *value) {
    return ZDStringFromSet(value, [NSSet setWithObjects:@"DRAFT", @"REWRITING", @"COMPLETED", @"FAILED", nil], @"DRAFT");
}

@implementation ZDCreateDramaInput
+ (instancetype)inputWithTitle:(NSString *)title
                        prompt:(NSString *)prompt
                         style:(NSString *)style
                targetAudience:(NSString *)targetAudience
                   aspectRatio:(NSString *)aspectRatio
                     shotCount:(NSInteger)shotCount
           shotDurationSeconds:(NSInteger)shotDurationSeconds {
    ZDCreateDramaInput *input = [ZDCreateDramaInput new];
    input.title = title ?: @"";
    input.prompt = prompt ?: @"";
    input.style = style ?: @"";
    input.targetAudience = targetAudience ?: @"";
    input.aspectRatio = aspectRatio ?: @"";
    input.shotCount = shotCount;
    input.shotDurationSeconds = shotDurationSeconds;
    return input;
}
@end

@implementation ZDDramaProject
@end

@implementation ZDEpisode
@end

@implementation ZDStoryboardShot
- (instancetype)init {
    self = [super init];
    if (self) {
        _scene = @"";
        _action = @"";
        _dialogue = @"";
        _camera = @"";
        _imagePrompt = @"";
        _videoPrompt = @"";
        _characterNames = @[];
        _imageStatus = @"PENDING";
        _videoStatus = @"PENDING";
        _episodeIdIsNull = YES;
    }
    return self;
}
@end

@implementation ZDCharacter
- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _role = @"";
        _characterDescription = @"";
        _appearance = @"";
        _personality = @"";
        _imageStatus = @"PENDING";
        _episodeIdIsNull = YES;
    }
    return self;
}
@end
