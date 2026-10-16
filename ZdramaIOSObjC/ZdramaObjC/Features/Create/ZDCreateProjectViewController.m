#import "ZDCreateProjectViewController.h"
#import "ZDAppContainer.h"
#import "ZDCreateDramaUseCase.h"
#import "ZDProjectDetailViewController.h"

@implementation ZDCreateProjectViewController {
    UITextField *_titleField;
    UITextView *_prompt;
    UITextField *_style;
    UITextField *_audience;
    UITextField *_aspect;
    UITextField *_shotCount;
    UITextField *_duration;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"新建";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _titleField = [self field:@"标题" text:@""];
    _prompt = [UITextView new];
    _prompt.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _prompt.layer.borderWidth = 1;
    _prompt.layer.borderColor = UIColor.separatorColor.CGColor;
    _style = [self field:@"风格" text:@"现代短剧"];
    _audience = [self field:@"受众" text:@"大众受众"];
    _aspect = [self field:@"画幅" text:@"9:16"];
    _shotCount = [self field:@"镜头数量" text:@"4"];
    _shotCount.keyboardType = UIKeyboardTypeNumberPad;
    _duration = [self field:@"单镜头时长" text:@"5"];
    _duration.keyboardType = UIKeyboardTypeNumberPad;
    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    [save setTitle:@"创建" forState:UIControlStateNormal];
    [save addTarget:self action:@selector(create) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleField, _prompt, _style, _audience, _aspect, _shotCount, _duration, save]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_prompt.heightAnchor constraintEqualToConstant:120]
    ]];
}

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text {
    UITextField *field = [UITextField new];
    field.placeholder = placeholder;
    field.text = text;
    field.borderStyle = UITextBorderStyleRoundedRect;
    return field;
}

- (void)create {
    ZDCreateDramaInput *input = [ZDCreateDramaInput inputWithTitle:_titleField.text ?: @""
                                                             prompt:_prompt.text ?: @""
                                                              style:_style.text ?: @""
                                                     targetAudience:_audience.text ?: @""
                                                        aspectRatio:_aspect.text ?: @""
                                                          shotCount:_shotCount.text.integerValue
                                                shotDurationSeconds:_duration.text.integerValue];
    NSError *error = nil;
    int64_t projectId = [[[ZDCreateDramaUseCase alloc] initWithRepository:ZDAppContainer.shared.repository] execute:input error:&error];
    if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self.navigationController pushViewController:[[ZDProjectDetailViewController alloc] initWithProjectId:projectId] animated:YES];
}

@end
