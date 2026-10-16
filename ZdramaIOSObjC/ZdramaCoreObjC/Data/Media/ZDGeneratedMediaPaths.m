#import "ZDGeneratedMediaPaths.h"

@interface ZDGeneratedMediaPaths ()
@property (nonatomic, copy) NSString *root;
@end

@implementation ZDGeneratedMediaPaths

- (instancetype)initWithRoot:(NSString *)root {
    self = [super init];
    if (self) {
        _root = [root copy] ?: @"";
    }
    return self;
}

- (NSURL *)projectDir:(int64_t)projectId {
    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/generated/%lld", self.root, projectId]];
}

- (NSURL *)shotImageProjectId:(int64_t)projectId shotId:(int64_t)shotId ext:(NSString *)ext {
    return [[self projectDir:projectId] URLByAppendingPathComponent:[NSString stringWithFormat:@"shot_%lld_image.%@", shotId, ext]];
}

- (NSURL *)shotVideoProjectId:(int64_t)projectId shotId:(int64_t)shotId ext:(NSString *)ext {
    return [[self projectDir:projectId] URLByAppendingPathComponent:[NSString stringWithFormat:@"shot_%lld_video.%@", shotId, ext]];
}

- (NSURL *)finalVideoProjectId:(int64_t)projectId episodeId:(int64_t)episodeId {
    return [[[self projectDir:projectId] URLByAppendingPathComponent:[NSString stringWithFormat:@"episode_%lld", episodeId]] URLByAppendingPathComponent:@"final_video.mp4"];
}

@end

static BOOL ZDExtensionIsValid(NSString *ext) {
    if (ext.length < 2 || ext.length > 5) {
        return NO;
    }
    for (NSUInteger i = 0; i < ext.length; i++) {
        unichar c = [ext characterAtIndex:i];
        BOOL digit = c >= '0' && c <= '9';
        BOOL letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
        if (!digit && !letter) {
            return NO;
        }
    }
    return YES;
}

NSString *ZDExtensionFromURL(NSString *url, NSString *kind) {
    NSString *path = [NSURL URLWithString:url].path ?: url;
    NSString *ext = path.pathExtension;
    if (ZDExtensionIsValid(ext)) {
        return ext;
    }
    return [kind isEqualToString:@"image"] ? @"jpg" : @"mp4";
}
