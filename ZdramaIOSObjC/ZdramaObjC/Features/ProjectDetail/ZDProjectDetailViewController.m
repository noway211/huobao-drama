#import "ZDProjectDetailViewController.h"
#import "ZDAppContainer.h"
#import "ZDGenerationPreflight.h"
#import "ZDScriptViewController.h"
#import "ZDStoryboardViewController.h"
#import "ZDImageGalleryViewController.h"
#import "ZDVideoPlayerViewController.h"

@implementation ZDProjectDetailViewController {
    int64_t _projectId;
    UILabel *_summary;
    NSArray<UIButton *> *_generationButtons;
    NSTimer *_poll;
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
    NSArray *titles = @[@"全部生成", @"剧本", @"改写", @"分镜", @"出图", @"出视频", @"成片", @"取消", @"查看剧本", @"查看分镜", @"图库", @"镜头视频", @"播放成片"];
    NSMutableArray *buttons = [NSMutableArray array];
    NSMutableArray *generation = [NSMutableArray array];
    for (NSString *title in titles) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:title forState:UIControlStateNormal];
        [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
        if ([@[@"全部生成", @"剧本", @"改写", @"分镜", @"出图", @"出视频", @"成片"] containsObject:title]) {
            [generation addObject:button];
        }
    }
    _generationButtons = generation;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:[@[_summary] arrayByAddingObjectsFromArray:buttons]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [self.view addSubview:scroll];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-32]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
    _poll = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(pollIfProcessing) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_poll invalidate];
    _poll = nil;
}

- (void)pollIfProcessing {
    if ([[ZDAppContainer.shared.repository getProject:_projectId].status isEqualToString:@"PROCESSING"]) [self reload];
}

- (void)reload {
    ZDDramaProject *project = [ZDAppContainer.shared.repository getProject:_projectId];
    self.title = project.title;
    _summary.text = [NSString stringWithFormat:@"状态 %@\n阶段 %@\n%@", project.status, project.currentStage, project.errorMessage ?: @""];
    BOOL processing = [project.status isEqualToString:@"PROCESSING"];
    for (UIButton *button in _generationButtons) button.enabled = !processing;
}

- (NSString *)stageForTitle:(NSString *)title {
    NSDictionary *stages = @{@"全部生成": @"full", @"剧本": @"text", @"改写": @"rewrite", @"分镜": @"storyboard", @"出图": @"image", @"出视频": @"video", @"成片": @"final_video"};
    return stages[title];
}

- (BOOL)needsOverwriteForStage:(NSString *)stage project:(ZDDramaProject *)project episode:(ZDEpisode *)episode shots:(NSArray<ZDStoryboardShot *> *)shots {
    BOOL script = episode.scriptContent.length > 0 || project.generatedScript.length > 0;
    if ([@[@"text", @"rewrite", @"full"] containsObject:stage]) return script;
    if ([stage isEqualToString:@"storyboard"]) return shots.count > 0;
    if ([stage isEqualToString:@"image"]) {
        for (ZDStoryboardShot *shot in shots) if ([shot.imageStatus isEqualToString:@"COMPLETED"]) return YES;
    }
    if ([stage isEqualToString:@"video"]) {
        for (ZDStoryboardShot *shot in shots) if ([shot.videoStatus isEqualToString:@"COMPLETED"]) return YES;
    }
    if ([stage isEqualToString:@"final_video"]) return [episode.finalVideoStatus isEqualToString:@"COMPLETED"] && episode.finalVideoLocalPath.length > 0;
    return NO;
}

- (void)tapped:(UIButton *)sender {
    if ([sender.currentTitle isEqualToString:@"取消"]) {
        ZDEpisode *episode = [ZDAppContainer.shared.repository getEpisodeForProject:_projectId];
        [ZDAppContainer.shared.coordinator cancelProjectId:_projectId episodeId:episode.id];
        [self reload];
        return;
    }
    NSString *stage = [self stageForTitle:sender.currentTitle];
    if (!stage) {
        UIViewController *viewer = nil;
        if ([sender.currentTitle isEqualToString:@"查看剧本"]) viewer = [[ZDScriptViewController alloc] initWithProjectId:_projectId];
        else if ([sender.currentTitle isEqualToString:@"查看分镜"]) viewer = [[ZDStoryboardViewController alloc] initWithProjectId:_projectId];
        else if ([sender.currentTitle isEqualToString:@"图库"]) viewer = [[ZDImageGalleryViewController alloc] initWithProjectId:_projectId];
        else if ([sender.currentTitle isEqualToString:@"镜头视频"]) viewer = [[ZDVideoPlayerViewController alloc] initWithProjectId:_projectId finalVideo:NO];
        else if ([sender.currentTitle isEqualToString:@"播放成片"]) viewer = [[ZDVideoPlayerViewController alloc] initWithProjectId:_projectId finalVideo:YES];
        if (viewer) [self.navigationController pushViewController:viewer animated:YES];
        return;
    }
    ZDDramaProject *project = [ZDAppContainer.shared.repository getProject:_projectId];
    ZDEpisode *episode = [ZDAppContainer.shared.repository getEpisodeForProject:_projectId];
    NSArray *shots = [ZDAppContainer.shared.repository getStoryboardsForEpisode:episode.id];
    NSError *error = ZDPreflightStage(stage, ZDAppContainer.shared.settingsStore.load.apiKey, episode.content, episode.scriptContent, shots, ^BOOL(NSString *path) {
        return [NSFileManager.defaultManager fileExistsAtPath:path];
    });
    if (error) {
        [self alert:error.localizedDescription];
        return;
    }
    if ([self needsOverwriteForStage:stage project:project episode:episode shots:shots]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:@"目标内容已存在，重新生成将覆盖现有结果，是否继续？" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"覆盖重新生成" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [ZDAppContainer.shared.coordinator enqueueProjectId:self->_projectId episodeId:episode.id stage:stage forceRegenerate:YES];
            [self reload];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [ZDAppContainer.shared.coordinator enqueueProjectId:_projectId episodeId:episode.id stage:stage forceRegenerate:NO];
    [self reload];
}

- (void)alert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
