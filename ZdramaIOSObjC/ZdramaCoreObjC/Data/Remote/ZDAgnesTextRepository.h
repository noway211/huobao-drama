#import <Foundation/Foundation.h>
#import "ZDAgnesSettings.h"
#import "ZDDramaModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesTextRepository : NSObject
- (instancetype)initWithSession:(NSURLSession *)session;
- (void)pingSettings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *_Nullable error))completion;
- (void)generateScriptSettings:(ZDAgnesSettings *)settings
                       project:(ZDDramaProject *)project
                   storyPrompt:(NSString *)storyPrompt
                    completion:(void (^)(NSString *_Nullable script, NSError *_Nullable error))completion;
- (void)rewriteScriptSettings:(ZDAgnesSettings *)settings
                   rawContent:(NSString *)rawContent
                   completion:(void (^)(NSString *_Nullable script, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
