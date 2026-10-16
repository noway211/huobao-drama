#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZDPromptDefaults : NSObject
@property (class, nonatomic, readonly) NSString *scriptCreatePrompt;
@property (class, nonatomic, readonly) NSString *scriptRewritePrompt;
@property (class, nonatomic, readonly) NSString *characterExtractPrompt;
@property (class, nonatomic, readonly) NSString *storyboardPrompt;
@end

NS_ASSUME_NONNULL_END
