#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesSettingsStore : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (ZDAgnesSettings *)load;
- (void)save:(ZDAgnesSettings *)settings;
@end

NS_ASSUME_NONNULL_END
