#import "ZDMediaDownloadRepository.h"
#import "ZDGeneratedMediaPaths.h"

static NSError *ZDDownloadError(NSString *message) {
    return [NSError errorWithDomain:@"ZDMediaDownloadRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZDMediaDownloadRepository {
    NSURLSession *_session;
    ZDGeneratedMediaPaths *_paths;
}

- (instancetype)initWithSession:(NSURLSession *)session filesRoot:(NSString *)filesRoot {
    self = [super init];
    if (self) {
        _session = session;
        _paths = [[ZDGeneratedMediaPaths alloc] initWithRoot:filesRoot];
    }
    return self;
}

- (void)downloadShotImageProjectId:(int64_t)projectId shotId:(int64_t)shotId url:(NSString *)url completion:(void (^)(NSString *path, NSError *error))completion {
    [self downloadProjectId:projectId shotId:shotId url:url kind:@"image" completion:completion];
}

- (void)downloadShotVideoProjectId:(int64_t)projectId shotId:(int64_t)shotId url:(NSString *)url completion:(void (^)(NSString *path, NSError *error))completion {
    [self downloadProjectId:projectId shotId:shotId url:url kind:@"video" completion:completion];
}

- (void)downloadProjectId:(int64_t)projectId shotId:(int64_t)shotId url:(NSString *)url kind:(NSString *)kind completion:(void (^)(NSString *path, NSError *error))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"GET";
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (error || http.statusCode < 200 || http.statusCode >= 300) {
            completion(nil, ZDDownloadError([NSString stringWithFormat:@"Media download failed: HTTP %ld", (long)http.statusCode]));
            return;
        }
        NSString *ext = ZDExtensionFromURL(url, kind);
        NSURL *dest = [kind isEqualToString:@"video"]
            ? [self->_paths shotVideoProjectId:projectId shotId:shotId ext:ext]
            : [self->_paths shotImageProjectId:projectId shotId:shotId ext:ext];
        [NSFileManager.defaultManager createDirectoryAtURL:[dest URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToURL:dest atomically:YES];
        completion(dest.path, nil);
    }] resume];
}

@end
