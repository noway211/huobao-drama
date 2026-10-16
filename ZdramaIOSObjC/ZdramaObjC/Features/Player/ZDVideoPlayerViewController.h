#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZDVideoPlayerViewController : UIViewController
- (instancetype)initWithProjectId:(int64_t)projectId finalVideo:(BOOL)finalVideo;
@end

NS_ASSUME_NONNULL_END
