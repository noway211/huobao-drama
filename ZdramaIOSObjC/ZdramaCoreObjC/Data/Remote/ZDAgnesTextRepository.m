#import "ZDAgnesTextRepository.h"
#import "ZDAgnesHTTPClient.h"

static BOOL ZDTextBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSError *ZDTextError(NSString *message) {
    return [NSError errorWithDomain:@"ZDAgnesTextRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDAgnesTextRepository {
    ZDAgnesHTTPClient *_client;
}

- (instancetype)initWithSession:(NSURLSession *)session {
    self = [super init];
    if (self) _client = [[ZDAgnesHTTPClient alloc] initWithSession:session];
    return self;
}

- (void)pingSettings:(ZDAgnesSettings *)settings completion:(void (^)(NSError *error))completion {
    if (ZDTextBlank(settings.apiKey)) {
        completion(ZDTextError(@"Agnes API Key is required"));
        return;
    }
    if (ZDTextBlank(settings.textModel)) {
        completion(ZDTextError(@"Text model is required"));
        return;
    }
    NSString *base = settings.baseUrl.length ? settings.baseUrl : @"https://apihub.agnes-ai.com/";
    if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
    NSURL *url = [NSURL URLWithString:@"v1/chat/completions" relativeToURL:[NSURL URLWithString:base]].absoluteURL;
    NSDictionary *body = @{
        @"model": settings.textModel,
        @"messages": @[@{@"role": @"user", @"content": @"ping"}],
        @"temperature": @0,
        @"max_tokens": @8
    };
    [_client jsonPOST:url body:body apiKey:settings.apiKey completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || ![response isKindOfClass:NSHTTPURLResponse.class]) {
            completion(ZDTextError(@"Agnes request failed: invalid response"));
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            NSString *responseBody = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
            NSString *message = responseBody.length == 0
                ? [NSString stringWithFormat:@"Agnes request failed: HTTP %ld", (long)response.statusCode]
                : [NSString stringWithFormat:@"Agnes request failed: HTTP %ld: %@", (long)response.statusCode, responseBody];
            completion(ZDTextError(message));
            return;
        }
        completion(nil);
    }];
}

@end
