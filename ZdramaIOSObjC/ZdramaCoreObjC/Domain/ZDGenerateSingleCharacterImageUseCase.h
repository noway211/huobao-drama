#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"
#import "ZDDramaRepository.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDGenerateSingleCharacterImageUseCase : NSObject
- (instancetype)initWithRepository:(ZDDramaRepository *)repository session:(NSURLSession *)session filesRoot:(NSString *)filesRoot;
- (void)executeProjectId:(int64_t)projectId
             characterId:(int64_t)characterId
                settings:(ZDAgnesSettings *)settings
              completion:(void (^)(NSString *_Nullable path, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
