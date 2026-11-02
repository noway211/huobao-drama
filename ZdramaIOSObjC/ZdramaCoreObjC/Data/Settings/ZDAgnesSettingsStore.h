#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesSettingsStore : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (ZDAgnesSettings *)load;
- (BOOL)save:(ZDAgnesSettings *)settings error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
