#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesTextRepository : NSObject
- (instancetype)initWithSession:(NSURLSession *)session;
- (void)pingSettings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
