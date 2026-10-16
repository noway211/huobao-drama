#import "ZDManagePromptsViewController.h"
#import "ZDAppContainer.h"
#import "ZDPromptDefaults.h"
#import "ZDPromptResolver.h"

@implementation ZDManagePromptsViewController {
    UISegmentedControl *_tabs;
    UITextView *_editor;
    NSMutableArray<NSString *> *_drafts;
    NSMutableArray<NSString *> *_saved;
    NSInteger _current;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"提示词";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    ZDAgnesSettings *settings = ZDAppContainer.shared.settingsStore.load;
    _drafts = [@[
        ZDResolvePrompt(settings.customScriptCreatePrompt, ZDPromptDefaults.scriptCreatePrompt),
        ZDResolvePrompt(settings.customScriptRewritePrompt, ZDPromptDefaults.scriptRewritePrompt),
        ZDResolvePrompt(settings.customStoryboardPrompt, ZDPromptDefaults.storyboardPrompt)
    ] mutableCopy];
    _saved = [_drafts mutableCopy];
    _tabs = [[UISegmentedControl alloc] initWithItems:@[@"创作", @"改写", @"分镜"]];
    _tabs.selectedSegmentIndex = 0;
    [_tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    _editor = [UITextView new];
    _editor.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _editor.layer.borderColor = UIColor.separatorColor.CGColor;
    _editor.layer.borderWidth = 1;
    _editor.text = _drafts[0];
    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    [save setTitle:@"保存" forState:UIControlStateNormal];
    [save addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
    UIButton *restore = [UIButton buttonWithType:UIButtonTypeSystem];
    [restore setTitle:@"恢复默认" forState:UIControlStateNormal];
    [restore addTarget:self action:@selector(restore) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[restore, save]];
    actions.distribution = UIStackViewDistributionFillEqually;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_tabs, _editor, actions]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [_editor.heightAnchor constraintGreaterThanOrEqualToConstant:240]
    ]];
}

- (void)tabChanged:(UISegmentedControl *)control {
    NSInteger next = control.selectedSegmentIndex;
    if (next == _current) return;
    if (![_editor.text isEqualToString:_saved[_current]]) {
        control.selectedSegmentIndex = _current;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"当前提示词已修改" message:@"离开当前标签页将丢失尚未保存的修改" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"继续编辑" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"放弃修改" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            self->_drafts[self->_current] = self->_saved[self->_current];
            [self showTab:next];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    _drafts[_current] = _editor.text ?: @"";
    [self showTab:next];
}

- (void)showTab:(NSInteger)index {
    _current = index;
    _tabs.selectedSegmentIndex = index;
    _editor.text = _drafts[index];
}

- (void)restore {
    NSArray *defaults = @[ZDPromptDefaults.scriptCreatePrompt, ZDPromptDefaults.scriptRewritePrompt, ZDPromptDefaults.storyboardPrompt];
    _drafts[_current] = defaults[_current];
    _editor.text = defaults[_current];
}

- (void)save {
    ZDAgnesSettings *settings = ZDAppContainer.shared.settingsStore.load;
    NSString *value = [_editor.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (_current == 0) settings.customScriptCreatePrompt = value;
    else if (_current == 1) settings.customScriptRewritePrompt = value;
    else settings.customStoryboardPrompt = value;
    [ZDAppContainer.shared.settingsStore save:settings];
    ZDAgnesSettings *reloaded = ZDAppContainer.shared.settingsStore.load;
    _saved = [@[
        ZDResolvePrompt(reloaded.customScriptCreatePrompt, ZDPromptDefaults.scriptCreatePrompt),
        ZDResolvePrompt(reloaded.customScriptRewritePrompt, ZDPromptDefaults.scriptRewritePrompt),
        ZDResolvePrompt(reloaded.customStoryboardPrompt, ZDPromptDefaults.storyboardPrompt)
    ] mutableCopy];
    _drafts[_current] = _saved[_current];
    _editor.text = _saved[_current];
}

@end
