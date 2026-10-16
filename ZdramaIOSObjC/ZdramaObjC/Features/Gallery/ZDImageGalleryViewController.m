#import "ZDImageGalleryViewController.h"
#import "ZDAppContainer.h"

@implementation ZDImageGalleryViewController {
    int64_t _projectId;
}

- (instancetype)initWithProjectId:(int64_t)projectId {
    self = [super init];
    if (self) _projectId = projectId;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"图库";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    ZDEpisode *episode = [ZDAppContainer.shared.repository getEpisodeForProject:_projectId];
    NSMutableArray *rows = [NSMutableArray array];
    for (ZDStoryboardShot *shot in [ZDAppContainer.shared.repository getStoryboardsForEpisode:episode.id]) {
        UILabel *label = [UILabel new];
        label.text = [NSString stringWithFormat:@"#%ld", (long)shot.shotNumber];
        UIImage *image = shot.imageLocalPath.length > 0 ? [UIImage imageWithContentsOfFile:shot.imageLocalPath] : nil;
        if (image) {
            UIImageView *view = [[UIImageView alloc] initWithImage:image];
            view.contentMode = UIViewContentModeScaleAspectFit;
            [view.heightAnchor constraintEqualToConstant:180].active = YES;
            [rows addObject:[[UIStackView alloc] initWithArrangedSubviews:@[label, view]]];
            ((UIStackView *)rows.lastObject).axis = UILayoutConstraintAxisVertical;
        } else {
            [rows addObject:label];
        }
    }
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:rows];
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
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:16],
        [content.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.widthAnchor]
    ]];
}

@end
