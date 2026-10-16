#import <Foundation/Foundation.h>
#import "ZDDramaRepository.h"
#import "ZDAgnesSettingsStore.h"
#import "ZDGenerationCoordinator.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAppContainer : NSObject
@property (nonatomic, readonly) ZDDramaRepository *repository;
@property (nonatomic, readonly) ZDAgnesSettingsStore *settingsStore;
@property (nonatomic, readonly) ZDGenerationCoordinator *coordinator;
@property (nonatomic, readonly, copy) NSString *filesRoot;
+ (instancetype)shared;
@end

NS_ASSUME_NONNULL_END
