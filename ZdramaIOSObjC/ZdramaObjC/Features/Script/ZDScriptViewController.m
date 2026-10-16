#import "ZDScriptViewController.h"
#import "ZDAppContainer.h"

@implementation ZDScriptViewController {
    int64_t _projectId;
}

- (instancetype)initWithProjectId:(int64_t)projectId {
    self = [super init];
    if (self) _projectId = projectId;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"剧本";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *text = [UITextView new];
    text.editable = NO;
    text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    text.text = [ZDAppContainer.shared.repository getEpisodeForProject:_projectId].scriptContent ?: @"";
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:text];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [text.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [text.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [text.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [text.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
}

@end
