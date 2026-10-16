#import "ZDAgnesHTTPClient.h"

@implementation ZDAgnesHTTPClient {
    NSURLSession *_session;
}

- (instancetype)initWithSession:(NSURLSession *)session {
    self = [super init];
    if (self) _session = session ?: NSURLSession.sharedSession;
    return self;
}

- (instancetype)init {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 120;
    configuration.timeoutIntervalForResource = 120;
    return [self initWithSession:[NSURLSession sessionWithConfiguration:configuration]];
}

- (void)jsonPOST:(NSURL *)url body:(NSDictionary *)body apiKey:(NSString *)apiKey completion:(ZDHTTPCompletion)completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey ?: @""] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:nil];
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        completion(data, (NSHTTPURLResponse *)response, error);
    }] resume];
}

@end
