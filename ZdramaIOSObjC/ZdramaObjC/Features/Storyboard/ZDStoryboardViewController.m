#import "ZDStoryboardViewController.h"
#import "ZDAppContainer.h"

@interface ZDShotPromptCard : UIView
@property (nonatomic) int64_t shotId;
@property (nonatomic) UITextView *imagePrompt;
@property (nonatomic) UITextView *videoPrompt;
@end

@implementation ZDShotPromptCard
@end

@implementation ZDStoryboardViewController {
    int64_t _projectId;
}

- (instancetype)initWithProjectId:(int64_t)projectId {
    self = [super init];
    if (self) _projectId = projectId;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"分镜";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    ZDEpisode *episode = [ZDAppContainer.shared.repository getEpisodeForProject:_projectId];
    NSMutableArray *cards = [NSMutableArray array];
    for (ZDStoryboardShot *shot in [ZDAppContainer.shared.repository getStoryboardsForEpisode:episode.id]) {
        ZDShotPromptCard *card = [ZDShotPromptCard new];
        card.shotId = shot.id;
        card.layer.borderWidth = 1;
        card.layer.borderColor = UIColor.separatorColor.CGColor;
        UILabel *title = [UILabel new];
        title.text = [NSString stringWithFormat:@"#%ld %@", (long)shot.shotNumber, shot.scene ?: @""];
        card.imagePrompt = [self editor:shot.imagePrompt];
        card.videoPrompt = [self editor:shot.videoPrompt];
        UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
        [save setTitle:@"保存" forState:UIControlStateNormal];
        [save addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, card.imagePrompt, card.videoPrompt, save]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],
            [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:8],
            [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8],
            [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8]
        ]];
        [cards addObject:card];
    }
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:cards];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 16;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];
    [self.view addSubview:scroll];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:16],
        [content.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-16],
        [content.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-16],
        [content.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-32]
    ]];
}

- (UITextView *)editor:(NSString *)text {
    UITextView *view = [UITextView new];
    view.text = text;
    view.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    view.layer.borderWidth = 1;
    view.layer.borderColor = UIColor.separatorColor.CGColor;
    [view.heightAnchor constraintEqualToConstant:72].active = YES;
    return view;
}

- (void)save:(UIButton *)sender {
    ZDShotPromptCard *card = (ZDShotPromptCard *)sender.superview.superview;
    [ZDAppContainer.shared.repository updateShotPromptsForShotId:card.shotId imagePrompt:card.imagePrompt.text videoPrompt:card.videoPrompt.text];
}

@end
