#import <Foundation/Foundation.h>
#import "ZDDramaRepository.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCreateDramaUseCase : NSObject
- (instancetype)initWithRepository:(ZDDramaRepository *)repository;
- (int64_t)execute:(ZDCreateDramaInput *)input error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
