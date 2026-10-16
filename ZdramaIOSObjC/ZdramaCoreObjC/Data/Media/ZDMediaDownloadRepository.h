#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZDMediaDownloadRepository : NSObject
- (instancetype)initWithSession:(NSURLSession *)session filesRoot:(NSString *)filesRoot;
- (void)downloadShotImageProjectId:(int64_t)projectId
                            shotId:(int64_t)shotId
                               url:(NSString *)url
                        completion:(void (^)(NSString *_Nullable path, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
