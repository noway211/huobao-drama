#import "ZDAgnesImageRepository.h"
#import "ZDAgnesHTTPClient.h"

static BOOL ZDImageBlank(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

static NSError *ZDImageError(NSString *message) {
    return [NSError errorWithDomain:@"ZDAgnesImageRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDAgnesImageRepository {
    ZDAgnesHTTPClient *_client;
}

- (instancetype)initWithSession:(NSURLSession *)session {
    self = [super init];
    if (self) _client = [[ZDAgnesHTTPClient alloc] initWithSession:session];
    return self;
}

- (void)generateImageSettings:(ZDAgnesSettings *)settings prompt:(NSString *)prompt completion:(void (^)(NSString *url, NSError *error))completion {
    if (ZDImageBlank(settings.apiKey) || ZDImageBlank(settings.imageModel)) {
        completion(nil, ZDImageError(ZDImageBlank(settings.apiKey) ? @"Agnes API Key is required" : @"Image model is required"));
        return;
    }
    NSString *base = [settings.baseUrl hasSuffix:@"/"] ? settings.baseUrl : [settings.baseUrl stringByAppendingString:@"/"];
    NSURL *url = [NSURL URLWithString:@"v1/images/generations" relativeToURL:[NSURL URLWithString:base]].absoluteURL;
    NSDictionary *body = @{@"model": settings.imageModel, @"prompt": prompt ?: @"", @"size": @"1024x768", @"n": @1, @"extra_body": @{@"response_format": @"url"}};
    [_client jsonPOST:url body:body apiKey:settings.apiKey completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error || response.statusCode < 200 || response.statusCode >= 300) {
            completion(nil, ZDImageError([NSString stringWithFormat:@"Agnes request failed: HTTP %ld", (long)response.statusCode]));
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *imageURL = json[@"data"][0][@"url"];
        if (ZDImageBlank(imageURL)) imageURL = json[@"url"];
        completion(ZDImageBlank(imageURL) ? nil : imageURL, ZDImageBlank(imageURL) ? ZDImageError(@"No image URL in Agnes response") : nil);
    }];
}

@end
