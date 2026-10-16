#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ZDExtensionFromURL(NSString *url, NSString *kind);

@interface ZDGeneratedMediaPaths : NSObject
- (instancetype)initWithRoot:(NSString *)root;
- (NSURL *)projectDir:(int64_t)projectId;
- (NSURL *)shotImageProjectId:(int64_t)projectId shotId:(int64_t)shotId ext:(NSString *)ext;
- (NSURL *)shotVideoProjectId:(int64_t)projectId shotId:(int64_t)shotId ext:(NSString *)ext;
- (NSURL *)finalVideoProjectId:(int64_t)projectId episodeId:(int64_t)episodeId;
@end

NS_ASSUME_NONNULL_END
