#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZDAgnesSettings : NSObject
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseUrl;
@property (nonatomic, copy) NSString *textModel;
@property (nonatomic, copy) NSString *imageModel;
@property (nonatomic, copy) NSString *videoModel;
@property (nonatomic) NSInteger requestTimeoutSeconds;
@property (nonatomic, copy, nullable) NSString *customScriptCreatePrompt;
@property (nonatomic, copy, nullable) NSString *customScriptRewritePrompt;
@property (nonatomic, copy, nullable) NSString *customCharacterExtractPrompt;
@property (nonatomic, copy, nullable) NSString *customStoryboardPrompt;
@end

FOUNDATION_EXPORT ZDAgnesSettings *ZDAgnesSettingsDefaults(void);

NS_ASSUME_NONNULL_END
