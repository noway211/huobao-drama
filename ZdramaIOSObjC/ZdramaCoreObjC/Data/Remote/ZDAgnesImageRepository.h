#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesImageRepository : NSObject
- (instancetype)initWithSession:(NSURLSession *)session;
- (void)generateImageSettings:(ZDAgnesSettings *)settings
                       prompt:(NSString *)prompt
                   completion:(void (^)(NSString *_Nullable url, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
