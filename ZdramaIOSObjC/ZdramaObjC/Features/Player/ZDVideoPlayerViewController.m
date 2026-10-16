#import "ZDVideoPlayerViewController.h"
#import "ZDAppContainer.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

@implementation ZDVideoPlayerViewController {
    int64_t _projectId;
    BOOL _finalVideo;
    NSArray<ZDStoryboardShot *> *_shots;
    NSInteger _index;
    AVPlayerViewController *_player;
    UILabel *_missing;
}

- (instancetype)initWithProjectId:(int64_t)projectId finalVideo:(BOOL)finalVideo {
    self = [super init];
    if (self) {
        _projectId = projectId;
        _finalVideo = finalVideo;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _finalVideo ? @"成片" : @"镜头视频";
    self.view.backgroundColor = UIColor.blackColor;
    _player = [AVPlayerViewController new];
    [self addChildViewController:_player];
    _player.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_player.view];
    [_player didMoveToParentViewController:self];
    _missing = [UILabel new];
    _missing.textColor = UIColor.whiteColor;
    _missing.textAlignment = NSTextAlignmentCenter;
    _missing.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_missing];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_player.view.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_player.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_player.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_player.view.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-56],
        [_missing.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_missing.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    if (_finalVideo) {
        NSString *path = [ZDAppContainer.shared.repository getEpisodeForProject:_projectId].finalVideoLocalPath;
        if (path.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
            _missing.text = @"成片不存在";
            return;
        }
        _player.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
        return;
    }
    ZDEpisode *episode = [ZDAppContainer.shared.repository getEpisodeForProject:_projectId];
    _shots = [ZDAppContainer.shared.repository getStoryboardsForEpisode:episode.id];
    UIButton *previous = [self button:@"上一个" action:@selector(previous)];
    UIButton *next = [self button:@"下一个" action:@selector(next)];
    UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[previous, next]];
    controls.distribution = UIStackViewDistributionFillEqually;
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controls];
    [NSLayoutConstraint activateConstraints:@[
        [controls.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [controls.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [controls.heightAnchor constraintEqualToConstant:44]
    ]];
    [self playIndex:0];
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)previous { if (_index > 0) [self playIndex:_index - 1]; }
- (void)next { if (_index + 1 < (NSInteger)_shots.count) [self playIndex:_index + 1]; }

- (void)playIndex:(NSInteger)index {
    _index = index;
    if (_shots.count == 0) { _missing.text = @"没有镜头"; return; }
    ZDStoryboardShot *shot = _shots[index];
    self.title = [NSString stringWithFormat:@"镜头 %ld", (long)shot.shotNumber];
    NSURL *url = nil;
    if (shot.videoLocalPath.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:shot.videoLocalPath]) {
        url = [NSURL fileURLWithPath:shot.videoLocalPath];
    } else if (shot.videoUrl.length > 0) {
        url = [NSURL URLWithString:shot.videoUrl];
    }
    _missing.text = url ? @"" : @"视频不存在";
    _player.player = url ? [AVPlayer playerWithURL:url] : nil;
}

@end
