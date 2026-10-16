#import "ZDProjectDetailViewController.h"
#import "ZDAppContainer.h"

@implementation ZDProjectDetailViewController {
    int64_t _projectId;
    UILabel *_summary;
}

- (instancetype)initWithProjectId:(int64_t)projectId {
    self = [super init];
    if (self) _projectId = projectId;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _summary = [UILabel new];
    _summary.numberOfLines = 0;
    _summary.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_summary];
    [NSLayoutConstraint activateConstraints:@[
        [_summary.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [_summary.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_summary.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ZDDramaProject *project = [ZDAppContainer.shared.repository getProject:_projectId];
    self.title = project.title;
    _summary.text = [NSString stringWithFormat:@"%@\n%@ · %@ · %ld 镜 · %ld 秒", project.prompt, project.style, project.aspectRatio, (long)project.shotCount, (long)project.shotDurationSeconds];
}

@end
