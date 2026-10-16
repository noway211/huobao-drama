#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL ZDValidateComposeInputs(NSArray<NSString *> *paths, NSError *_Nullable *_Nullable error);

@interface ZDLocalMp4Composer : NSObject
- (BOOL)composePaths:(NSArray<NSString *> *)paths toURL:(NSURL *)output error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
