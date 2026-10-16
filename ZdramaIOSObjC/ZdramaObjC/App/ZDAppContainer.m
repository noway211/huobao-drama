#import "ZDAppContainer.h"

@implementation ZDAppContainer

+ (instancetype)shared {
    static ZDAppContainer *container;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        container = [ZDAppContainer new];
    });
    return container;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *appDir = [support URLByAppendingPathComponent:@"Zdrama" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:appDir withIntermediateDirectories:YES attributes:nil error:nil];
        _filesRoot = [appDir URLByAppendingPathComponent:@"media" isDirectory:YES].path;
        _repository = [ZDDramaRepository repositoryWithDatabasePath:[appDir URLByAppendingPathComponent:@"zdrama.db"].path filesRoot:_filesRoot];
        _settingsStore = [[ZDAgnesSettingsStore alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        _coordinator = [[ZDGenerationCoordinator alloc] initWithRepository:_repository
                                                                   session:NSURLSession.sharedSession
                                                                 filesRoot:_filesRoot
                                                             settingsStore:_settingsStore];
        [_coordinator failInterruptedWorkWithMessage:@"生成任务中断（应用被关闭），请重新开始"];
    }
    return self;
}

@end
