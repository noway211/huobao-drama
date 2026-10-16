#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"
#import "ZDDramaModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesVideoRepository : NSObject
- (instancetype)initWithSession:(NSURLSession *)session pollDelay:(NSTimeInterval)pollDelay;
- (void)generateVideoSettings:(ZDAgnesSettings *)settings
                         shot:(ZDStoryboardShot *)shot
                   completion:(void (^)(NSString *_Nullable url, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
