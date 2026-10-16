#import "ZDCreateDramaUseCase.h"

@implementation ZDCreateDramaUseCase {
    ZDDramaRepository *_repository;
}

- (instancetype)initWithRepository:(ZDDramaRepository *)repository {
    self = [super init];
    if (self) _repository = repository;
    return self;
}

- (int64_t)execute:(ZDCreateDramaInput *)input error:(NSError **)error {
    NSString *title = [input.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *prompt = [input.prompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *message = nil;
    if (title.length == 0) message = @"请填写标题";
    else if (prompt.length == 0) message = @"请输入故事提示词";
    else if (input.shotCount <= 0 || input.shotDurationSeconds <= 0) message = @"镜头数量和时长必须大于 0";
    if (message) {
        if (error) *error = [NSError errorWithDomain:@"ZDCreateDramaUseCase" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
        return 0;
    }
    input.title = title;
    input.prompt = prompt;
    return [_repository createProjectFromInput:input];
}

@end
