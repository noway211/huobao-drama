#import <Foundation/Foundation.h>
#import "ZDDramaRepository.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDComposeFinalVideoUseCase : NSObject
- (instancetype)initWithRepository:(ZDDramaRepository *)repository filesRoot:(NSString *)filesRoot;
- (void)executeProjectId:(int64_t)projectId episodeId:(int64_t)episodeId completion:(void (^)(NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
