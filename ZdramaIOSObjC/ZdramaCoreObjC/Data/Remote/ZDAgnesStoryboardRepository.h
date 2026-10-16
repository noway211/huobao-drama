#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"
#import "ZDDramaModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesStoryboardRepository : NSObject
- (instancetype)initWithSession:(NSURLSession *)session;
- (void)generateStoryboardsSettings:(ZDAgnesSettings *)settings
                            project:(ZDDramaProject *)project
                             script:(NSString *)script
                         completion:(void (^)(NSArray<ZDStoryboardShot *> *_Nullable shots, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
