import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { SettingsStore } from '../data/SettingsStore';
import { DramaProject, Episode, AssetStatus } from '../model/DramaModels';
import { Theme, statusLabel, stageLabel } from '../common/Theme';

interface DetailParams {
  projectId: number;
}

@Entry
@Component
struct ProjectDetailPage {
  @State project: DramaProject | null = null;
  @State episode: Episode | null = null;
  @State busy: boolean = false;
  @State busyLabel: string = '';
  @State promptExpanded: boolean = false;
  @State hasStoryboards: boolean = false;
  @State hasImages: boolean = false;
  private projectId: number = 0;

  // 组件即将出现：从路由参数中读取项目 ID
  aboutToAppear(): void {
    const params = router.getParams() as DetailParams;
    if (params && params.projectId) {
      this.projectId = params.projectId;
    }
  }

  // 页面每次显示时重新加载数据
  onPageShow(): void {
    this.reload();
  }

  // 重新拉取项目与剧集数据
  async reload(): Promise<void> {
    this.project = await UseCases.getProject(this.projectId);
    this.episode = await UseCases.getEpisode(this.projectId);
    const storyboards = await UseCases.getStoryboards(this.projectId);
    this.hasStoryboards = storyboards.length > 0;
    this.hasImages = storyboards.some(s => s.imageStatus === AssetStatus.COMPLETED);
    // 自动修复触发内容审查的提示词
    await UseCases.patchSensitivePrompts(this.projectId);
  }

  // 是否已有脚本（剧集脚本或项目生成脚本任一非空）
  private hasScript(): boolean {
    const fromEpisode = this.episode?.scriptContent;
    const fromProject = this.project?.generatedScript;
    return (!!fromEpisode && fromEpisode.trim().length > 0) ||
      (!!fromProject && fromProject.trim().length > 0);
  }

  // 是否有可改写的原始内容（剧集 content 非空）
  private hasRawContent(): boolean {
    const raw = this.episode?.content;
    return !!raw && raw.trim().length > 0;
  }

  /**
   * 估算提示词是否超过 6 行，用于决定是否显示展开/收起按钮，对齐 Android 端逻辑。
   * ArkUI 无直接获取行数的 API，故按换行符与文本长度估算（窄屏每行约 24 字符）。
   * Heuristic mirror of Android's "only show toggle when prompt exceeds 6 lines".
   * ArkUI has no direct line-count API, so estimate from newlines and length
   * (~24 chars per line on a narrow phone column).
   */
  private promptOverflows(): boolean {
    const text = this.project?.prompt ?? '';
    if (text.length === 0) {
      return false;
    }
    let lines = 1;
    for (const ch of text) {
      if (ch === '\n') {
        lines++;
      }
    }
    const estimated = lines + Math.floor(text.length / 24);
    return estimated > 6;
  }

  // 执行前置校验：未配置 API Key 则提示并中断，否则执行传入动作
  private async runWithGuard(action: () => Promise<void>): Promise<void> {
    const hasKey = await SettingsStore.hasApiKey();
    if (!hasKey) {
      promptAction.showToast({ message: '请先在设置中填写 API Key' });
      return;
    }
    await action();
  }

  // 若已有脚本则弹窗二次确认，确认后再执行；无脚本直接执行
  private confirmIfScriptExists(message: string, onProceed: () => void): void {
    if (!this.hasScript()) {
      onProceed();
      return;
    }
    promptAction.showDialog({
      title: '重新生成？',
      message: message,
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '继续生成', color: Theme.primary }
      ]
    }).then((r) => {
      if (r.index === 1) {
        onProceed();
      }
    });
  }

  // 调用生成脚本用例，处理忙碌状态、结果提示并刷新数据
  async doGenerate(): Promise<void> {
    this.busy = true;
    this.busyLabel = '创作脚本中…';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateScript(this.projectId, settings);
    this.busy = false;
    promptAction.showToast({ message: result.ok ? '脚本已生成' : `失败：${result.error}` });
    await this.reload();
  }

  // 调用改写脚本用例：先校验有原始内容，再处理忙碌状态、结果提示并刷新
  async doRewrite(): Promise<void> {
    if (!this.hasRawContent()) {
      promptAction.showToast({ message: '没有可改写的原始内容，请先在故事提示词中输入剧情内容' });
      return;
    }
    this.busy = true;
    this.busyLabel = '改写脚本中…';
    const settings = await SettingsStore.load();
    const result = await UseCases.rewriteScript(this.projectId, settings);
    this.busy = false;
    promptAction.showToast({ message: result.ok ? '脚本已改写' : `失败：${result.error}` });
    await this.reload();
  }

  // 点击“创作脚本”：校验 Key 并在已有脚本时确认后执行生成
  onGenerateClick(): void {
    this.runWithGuard(async () => {
      this.confirmIfScriptExists(
        '当前项目已有脚本，重新创作脚本会影响后续分镜、图片、视频和成片。是否继续？',
        () => this.doGenerate());
    });
  }

  // 点击”改写脚本”：校验 Key 并在已有脚本时确认后执行改写
  onRewriteClick() {
    this.runWithGuard(async () => {
      this.confirmIfScriptExists(
        '当前已有改写后的脚本，重新改写会覆盖现有内容。是否继续？',
        () => this.doRewrite());
    });
  }

  // 执行分镜生成：更新 busy 状态，调用用例，提示结果后刷新
  async doGenerateStoryboards(): Promise<void> {
    this.busy = true;
    this.busyLabel = '生成分镜中…';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateStoryboards(this.projectId, settings);
    this.busy = false;
    promptAction.showToast({ message: result.ok ? '分镜已生成' : `失败：${result.error}` });
    await this.reload();
  }

  // 点击”生成分镜”：校验 Key，有已有分镜时确认后生成
  onGenerateStoryboardClick() {
    this.runWithGuard(async () => {
      if (this.hasStoryboards) {
        const r = await promptAction.showDialog({
          title: '重新生成？',
          message: '当前已有分镜，重新生成会覆盖现有内容。是否继续？',
          buttons: [
            { text: '取消', color: Theme.textSecondary },
            { text: '继续生成', color: Theme.primary }
          ]
        });
        if (r.index === 1) {
          this.doGenerateStoryboards();
        }
      } else {
        this.doGenerateStoryboards();
      }
    });
  }

  // 点击”查看分镜”：跳转到分镜查看页面
  onViewStoryboardClick() {
    if (!this.hasStoryboards) {
      promptAction.showToast({ message: '暂无分镜' });
      return;
    }
    router.pushUrl({ url: 'pages/StoryboardViewerPage', params: { projectId: this.projectId } });
  }

  // 执行图片生成：更新 busy 状态，调用用例，提示结果后刷新
  async doGenerateImages(): Promise<void> {
    this.busy = true;
    this.busyLabel = '生成图片中…';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateStoryboardImages(this.projectId, settings);
    this.busy = false;
    promptAction.showToast({ message: result.ok ? '图片已生成' : `失败：${result.error}` });
    await this.reload();
  }

  // 点击”生成图片”：校验 Key，有已有图片时确认后生成
  onGenerateImageClick() {
    this.runWithGuard(async () => {
      if (this.hasImages) {
        const r = await promptAction.showDialog({
          title: '重新生成？',
          message: '当前已有图片，重新生成会覆盖现有内容。是否继续？',
          buttons: [
            { text: '取消', color: Theme.textSecondary },
            { text: '继续生成', color: Theme.primary }
          ]
        });
        if (r.index === 1) {
          this.doGenerateImages();
        }
      } else {
        this.doGenerateImages();
      }
    });
  }

  // 弹窗确认删除当前项目，确认后删除并返回上一页
  confirmDelete(): void {
    promptAction.showDialog({
      title: '删除项目？',
      message: '这会删除项目与剧集内容。',
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '删除', color: Theme.primary }
      ]
    }).then(async (r) => {
      if (r.index === 1) {
        const ok = await UseCases.deleteProject(this.projectId);
        promptAction.showToast({ message: ok ? '项目已删除' : '项目删除失败' });
        if (ok) {
          router.back();
        }
      }
    });
  }

  // 信息行：左侧标签 + 右侧内容的一行展示
  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(Theme.textSecondary)
        .width(88)
      Text(value)
        .fontSize(14)
        .fontColor(Theme.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 10 })
  }

  // 页面整体布局：顶部返回/删除栏 + 项目信息、原始内容、脚本操作按钮的可滚动内容
  build() {
    Column() {
      // 顶部栏
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick(() => router.back())
        Text('项目详情')
          .fontSize(20)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .margin({ left: 12 })
        Button('删除')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.primary)
          .height(36)
          .enabled(!this.busy)
          .opacity(this.busy ? 0.5 : 1)
          .onClick(() => this.confirmDelete())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (!this.project) {
        Column() {
          LoadingProgress().width(48).height(48).color(Theme.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        Scroll() {
          Column() {
            Text(this.project.title)
              .fontSize(22)
              .fontColor(Theme.textPrimary)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .margin({ bottom: 16 })

            Column() {
              this.InfoRow('状态', statusLabel(this.project.status))
              this.InfoRow('当前阶段', stageLabel(this.project.currentStage))
              this.InfoRow('风格', this.project.style)
              this.InfoRow('受众', this.project.targetAudience)
              this.InfoRow('画幅', this.project.aspectRatio)
              this.InfoRow('分镜', `${this.project.shotCount} 镜 · 每镜 ${this.project.shotDurationSeconds}s`)
              if (this.project.errorMessage && this.project.errorMessage.length > 0) {
                this.InfoRow('错误', this.project.errorMessage)
              }
            }
            .padding(16)
            .width('100%')
            .backgroundColor(Theme.surface)
            .borderRadius(12)
            .margin({ bottom: 16 })

            // Prompt / raw content
            Column() {
              Text('原始内容')
                .fontSize(14)
                .fontColor(Theme.textSecondary)
                .width('100%')
                .margin({ bottom: 8 })
              Text(this.project.prompt)
                .fontSize(14)
                .fontColor(Theme.textPrimary)
                .width('100%')
                .maxLines(this.promptExpanded ? 1000 : 6)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.promptOverflows()) {
                Text(this.promptExpanded ? '收起' : '展开')
                  .fontSize(13)
                  .fontColor(Theme.primary)
                  .margin({ top: 8 })
                  .onClick(() => this.promptExpanded = !this.promptExpanded)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .width('100%')
            .backgroundColor(Theme.surface)
            .borderRadius(12)
            .margin({ bottom: 16 })

            // Script action buttons (3-col row: 创作 / 改写 / 查看)
            Row() {
              Button(this.busy ? this.busyLabel : '创作脚本')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy)
                .onClick(() => this.onGenerateClick())
              Button('改写脚本')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy)
                .margin({ left: 10 })
                .onClick(() => this.onRewriteClick())
            }
            .width('100%')
            .margin({ bottom: 10 })

            Button('查看脚本')
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor(Theme.textPrimary)
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(10)
              .enabled(this.hasScript())
              .opacity(this.hasScript() ? 1 : 0.5)
              .onClick(() => {
                router.pushUrl({ url: 'pages/ScriptViewerPage', params: { projectId: this.projectId } });
              })
              .margin({ bottom: 10 })

            // Storyboard action buttons (2-col row: 生成分镜 / 查看分镜)
            Row() {
              Button(this.busy ? this.busyLabel : '生成分镜')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy)
                .onClick(() => this.onGenerateStoryboardClick())
              Button('查看分镜')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Theme.textPrimary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(10)
                .enabled(!this.busy && this.hasStoryboards)
                .opacity(this.hasStoryboards ? 1 : 0.5)
                .margin({ left: 10 })
                .onClick(() => this.onViewStoryboardClick())
            }
            .width('100%')
            .margin({ bottom: 24 })

            // Image generation button row
            Row() {
              Button(this.busy ? this.busyLabel : '生成图片')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy)
                .onClick(() => this.onGenerateImageClick())
              Button('查看图片')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Theme.textPrimary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(10)
                .enabled(!this.busy && this.hasImages)
                .opacity(this.hasImages ? 1 : 0.5)
                .margin({ left: 10 })
                .onClick(() => {
                  router.pushUrl({ url: 'pages/StoryboardImagePage', params: { projectId: this.projectId } });
                })
            }
            .width('100%')
            .margin({ bottom: 24 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
