#import "ZDSettingsViewController.h"
#import "ZDAppContainer.h"
#import "ZDAgnesTextRepository.h"
#import "ZDManagePromptsViewController.h"

@implementation ZDSettingsViewController {
    UITextField *_apiKey;
    UITextField *_baseUrl;
    UITextField *_textModel;
    UITextField *_imageModel;
    UITextField *_videoModel;
    UILabel *_feedback;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    ZDAgnesSettings *settings = ZDAppContainer.shared.settingsStore.load;
    _apiKey = [self field:@"API Key" text:settings.apiKey secure:YES];
    _baseUrl = [self field:@"Base URL" text:settings.baseUrl secure:NO];
    _textModel = [self field:@"文本模型" text:settings.textModel secure:NO];
    _imageModel = [self field:@"图片模型" text:settings.imageModel secure:NO];
    _videoModel = [self field:@"视频模型" text:settings.videoModel secure:NO];
    _feedback = [UILabel new];
    _feedback.numberOfLines = 0;
    UIButton *save = [self button:@"保存" action:@selector(save)];
    UIButton *ping = [self button:@"测试连接" action:@selector(ping)];
    UIButton *prompts = [self button:@"提示词" action:@selector(openPrompts)];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_apiKey, _baseUrl, _textModel, _imageModel, _videoModel, save, ping, prompts, _feedback]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16]
    ]];
}

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text secure:(BOOL)secure {
    UITextField *field = [UITextField new];
    field.placeholder = placeholder;
    field.text = text;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.secureTextEntry = secure;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    return field;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (ZDAgnesSettings *)editedSettings {
    ZDAgnesSettings *settings = ZDAppContainer.shared.settingsStore.load;
    settings.apiKey = [_apiKey.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    settings.baseUrl = _baseUrl.text ?: @"";
    settings.textModel = _textModel.text ?: @"";
    settings.imageModel = _imageModel.text ?: @"";
    settings.videoModel = _videoModel.text ?: @"";
    return settings;
}

- (void)save {
    [ZDAppContainer.shared.settingsStore save:[self editedSettings]];
    _feedback.textColor = UIColor.systemGreenColor;
    _feedback.text = @"已保存";
}

- (void)ping {
    [ZDAppContainer.shared.settingsStore save:[self editedSettings]];
    _feedback.text = @"测试中…";
    ZDAgnesTextRepository *text = [[ZDAgnesTextRepository alloc] initWithSession:NSURLSession.sharedSession];
    [text pingSettings:ZDAppContainer.shared.settingsStore.load completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self->_feedback.textColor = UIColor.systemRedColor;
                self->_feedback.text = [NSString stringWithFormat:@"连接失败：%@", error.localizedDescription];
            } else {
                self->_feedback.textColor = UIColor.systemGreenColor;
                self->_feedback.text = @"连接成功";
            }
        });
    }];
}

- (void)openPrompts {
    [self.navigationController pushViewController:[ZDManagePromptsViewController new] animated:YES];
}

@end
