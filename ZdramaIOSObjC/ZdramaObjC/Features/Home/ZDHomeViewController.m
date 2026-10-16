#import "ZDHomeViewController.h"
#import "ZDSettingsViewController.h"

@implementation ZDHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"视频短剧";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"AI 驱动的短剧创作工具";
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        subtitle,
        [self buttonTitled:@"设置"],
        [self buttonTitled:@"新建"],
        [self buttonTitled:@"项目"]
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24]
    ]];
}

- (UIButton *)buttonTitled:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    [button addTarget:self action:@selector(openPlaceholder:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)openPlaceholder:(UIButton *)sender {
    if ([sender.currentTitle isEqualToString:@"设置"]) {
        [self.navigationController pushViewController:[ZDSettingsViewController new] animated:YES];
        return;
    }
    UIViewController *placeholder = [UIViewController new];
    placeholder.title = sender.currentTitle;
    placeholder.view.backgroundColor = UIColor.systemBackgroundColor;
    [self.navigationController pushViewController:placeholder animated:YES];
}

@end
