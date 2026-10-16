#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZDHTTPCompletion)(NSData *_Nullable data, NSHTTPURLResponse *_Nullable response, NSError *_Nullable error);

@interface ZDAgnesHTTPClient : NSObject
- (instancetype)initWithSession:(NSURLSession *)session;
- (void)jsonPOST:(NSURL *)url
            body:(NSDictionary *)body
          apiKey:(NSString *)apiKey
      completion:(ZDHTTPCompletion)completion;
@end

NS_ASSUME_NONNULL_END
