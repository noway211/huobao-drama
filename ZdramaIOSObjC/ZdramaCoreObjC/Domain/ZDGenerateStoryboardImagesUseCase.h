#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"
#import "ZDDramaRepository.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDGenerateStoryboardImagesUseCase : NSObject
- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session filesRoot:(NSString *)filesRoot;
- (void)executeProjectId:(int64_t)projectId episodeId:(int64_t)episodeId settings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
