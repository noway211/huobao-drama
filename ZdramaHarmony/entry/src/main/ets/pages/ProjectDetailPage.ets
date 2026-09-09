import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { SettingsStore } from '../data/SettingsStore';
import { DramaProject, Episode, Character, AssetStatus } from '../model/DramaModels';
import { Theme, statusLabel, stageLabel } from '../common/Theme';

interface DetailParams {
  projectId: number;
}

// 「新增剧集」对话框：标题 + 内容（内容可为空），确认后回调 onConfirm
@CustomDialog
struct AddEpisodeDialog {
  controller: CustomDialogController;
  onConfirm: (title: string, content: string) => void = () => {
  };
  @State title: string = '';
  @State content: string = '';

  build() {
    Column() {
      Text('新增剧集')
        .fontSize(17)
        .fontColor(Theme.textPrimary)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .margin({ bottom: 16 })
      TextInput({ text: this.title, placeholder: '标题（可为空）' })
        .fontColor(Theme.textPrimary)
        .placeholderColor(Theme.textHint)
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(8)
        .width('100%')
        .height(44)
        .onChange((v: string) => this.title = v)
      TextArea({ text: this.content, placeholder: '剧情内容（可为空）' })
        .fontColor(Theme.textPrimary)
        .placeholderColor(Theme.textHint)
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(8)
        .width('100%')
        .height(120)
        .margin({ top: 10 })
        .onChange((v: string) => this.content = v)
      Row() {
        Button('取消')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(40)
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Button('创建')
          .fontSize(14)
          .backgroundColor(Theme.primary)
          .fontColor(Color.White)
          .height(40)
          .layoutWeight(1)
          .margin({ left: 10 })
          .onClick(() => {
            this.onConfirm(this.title.trim(), this.content.trim());
            this.controller.close();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .borderRadius(12)
    .backgroundColor(Theme.bg)
    .width('86%')
  }
}

@Entry
@Component
struct ProjectDetailPage {
  @State project: DramaProject | null = null;
  @State episodes: Episode[] = [];
  @State episode: Episode | null = null;
  @State currentEpisodeId: number = 0;
  @State busy: boolean = false;
  @State busyLabel: string = '';
  // 阶段进度：阶段名 + 当前/总数 + 正在处理的对象（仅分镜图/视频/角色图三类有 callback）
  @State stageLabel: string = '';
  @State progressCurrent: number = 0;
  @State progressTotal: number = 0;
  @State progressEntity: string = '';
  @State promptExpanded: boolean = false;
  @State hasStoryboards: boolean = false;
  @State characters: Character[] = [];
  @State hasCharacters: boolean = false;
  @State hasCharacterImages: boolean = false;
  @State hasImages: boolean = false;
  @State hasVideos: boolean = false;
  @State hasFinalVideo: boolean = false;
  private projectId: number = 0;
  // 新增剧集对话框（懒初始化：aboutToAppear 时创建，避免成员初始化器不能引用 this）
  private addEpisodeDialog: CustomDialogController | null = null;

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

  // 重新拉取项目、剧集与当前集分镜数据
  async reload(): Promise<void> {
    this.project = await UseCases.getProject(this.projectId);
    const episodes = await UseCases.getEpisodes(this.projectId);
    this.episodes = episodes;
    // 当前集不存在（未选择或已删除）时回退到第一集
    if (episodes.length > 0 &&
      (this.currentEpisodeId <= 0 || !episodes.some(ep => ep.id === this.currentEpisodeId))) {
      this.currentEpisodeId = episodes[0].id;
    }
    this.episode = episodes.find(ep => ep.id === this.currentEpisodeId) ?? null;
    const storyboards = this.currentEpisodeId > 0
      ? await UseCases.getStoryboardsForEpisode(this.projectId, this.currentEpisodeId)
      : [];
    this.hasStoryboards = storyboards.length > 0;
    this.characters = await UseCases.getCharacters(this.projectId);
    this.hasCharacters = this.characters.length > 0;
    this.hasCharacterImages = this.characters.some(c => c.imageStatus === AssetStatus.COMPLETED);
    this.hasImages = storyboards.some(s => s.imageStatus === AssetStatus.COMPLETED);
    this.hasVideos = storyboards.some(s => s.videoStatus === AssetStatus.COMPLETED);
    this.hasFinalVideo = this.episode?.finalVideoStatus === AssetStatus.COMPLETED &&
      (this.episode?.finalVideoLocalPath?.length ?? 0) > 0;
    // 自动修复触发内容审查的提示词
    await UseCases.patchSensitivePrompts(this.projectId);
  }

  // 是否已有脚本（当前集脚本或项目生成脚本任一非空）
  private hasScript(): boolean {
    const fromEpisode = this.episode?.scriptContent;
    const fromProject = this.project?.generatedScript;
    return (!!fromEpisode && fromEpisode.trim().length > 0) ||
      (!!fromProject && fromProject.trim().length > 0);
  }

  // 是否有可改写的原始内容（当前集 content 非空）
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
    this.stageLabel = '创作脚本';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateScript(this.projectId, this.currentEpisodeId, settings);
    this.busy = false;
    this.clearProgress();
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
    this.stageLabel = '改写脚本';
    const settings = await SettingsStore.load();
    const result = await UseCases.rewriteScript(this.projectId, this.currentEpisodeId, settings);
    this.busy = false;
    this.clearProgress();
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
    this.stageLabel = '生成分镜';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateStoryboards(this.projectId, this.currentEpisodeId, settings);
    this.busy = false;
    this.clearProgress();
    promptAction.showToast({ message: result.ok ? '分镜已生成' : `失败：${result.error}` });
    await this.reload();
  }

  // 点击”查看脚本”：跳转到脚本查看页面
  onViewScriptClick() {
    if (!this.hasScript()) {
      promptAction.showToast({ message: '暂无脚本' });
      return;
    }
    router.pushUrl({ url: 'pages/ScriptViewerPage', params: { projectId: this.projectId, episodeId: this.currentEpisodeId } });
  }

  // 执行角色提取：从当前集剧本中提取角色信息
  async doExtractCharacters(): Promise<void> {
    this.busy = true;
    this.busyLabel = '提取角色中…';
    this.stageLabel = '提取角色';
    const settings = await SettingsStore.load();
    const result = await UseCases.extractCharacters(this.projectId, this.currentEpisodeId, settings);
    this.busy = false;
    this.clearProgress();
    promptAction.showToast({ message: result.ok ? `已提取 ${result.value} 个角色` : `失败：${result.error}` });
    await this.reload();
  }

  // 点击”提取角色”
  onExtractCharactersClick() {
    this.runWithGuard(async () => {
      if (this.hasCharacters) {
        const r = await promptAction.showDialog({
          title: '重新提取？',
          message: '当前已有角色，重新提取会覆盖现有内容。是否继续？',
          buttons: [
            { text: '取消', color: Theme.textSecondary },
            { text: '继续提取', color: Theme.primary }
          ]
        });
        if (r.index === 1) {
          this.doExtractCharacters();
        }
      } else {
        this.doExtractCharacters();
      }
    });
  }

  // 执行角色图生成
  async doGenerateCharacterImages(): Promise<void> {
    this.busy = true;
    this.busyLabel = '生成角色图中…';
    this.stageLabel = '生成角色图';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateCharacterImages(this.projectId, settings, (current, total, shotNumber, phase) => {
      this.busyLabel = `${phase} ${current}/${total}`;
      this.progressCurrent = current;
      this.progressTotal = total;
      this.progressEntity = `角色 #${shotNumber}`;
    });
    this.busy = false;
    this.clearProgress();
    promptAction.showToast({ message: result.ok ? '角色图已生成' : `失败：${result.error}` });
    await this.reload();
  }

  // 点击”生成角色图”
  onGenerateCharacterImagesClick() {
    this.runWithGuard(async () => {
      if (this.hasCharacterImages) {
        const r = await promptAction.showDialog({
          title: '重新生成？',
          message: '当前已有角色图，重新生成会覆盖现有内容。是否继续？',
          buttons: [
            { text: '取消', color: Theme.textSecondary },
            { text: '继续生成', color: Theme.primary }
          ]
        });
        if (r.index === 1) {
          this.doGenerateCharacterImages();
        }
      } else {
        this.doGenerateCharacterImages();
      }
    });
  }

  // 点击“生成分镜”：校验 Key，有已有分镜时确认后生成
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
    router.pushUrl({ url: 'pages/StoryboardViewerPage', params: { projectId: this.projectId, episodeId: this.currentEpisodeId } });
  }

  // 执行图片生成：更新 busy 状态，调用用例，提示结果后刷新
  async doGenerateImages(): Promise<void> {
    this.busy = true;
    this.busyLabel = '生成图片中…';
    this.stageLabel = '生成图片';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateStoryboardImages(this.projectId, this.currentEpisodeId, settings, (current, total, shotNumber, phase) => {
      this.busyLabel = `${phase} ${current}/${total}（分镜 ${shotNumber}）`;
      this.progressCurrent = current;
      this.progressTotal = total;
      this.progressEntity = `分镜 #${shotNumber}`;
    });
    this.busy = false;
    this.clearProgress();
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

  // 执行视频生成：更新 busy 状态，调用用例，提示结果后刷新
  async doGenerateVideos(): Promise<void> {
    this.busy = true;
    this.busyLabel = '生成视频中…';
    this.stageLabel = '生成视频';
    const settings = await SettingsStore.load();
    const result = await UseCases.generateStoryboardVideos(this.projectId, this.currentEpisodeId, settings, (current, total, shotNumber, phase) => {
      this.busyLabel = `${phase} ${current}/${total}（分镜 ${shotNumber}）`;
      this.progressCurrent = current;
      this.progressTotal = total;
      this.progressEntity = `分镜 #${shotNumber}`;
    });
    this.busy = false;
    this.clearProgress();
    promptAction.showToast({ message: result.ok ? '视频已生成' : `失败：${result.error}` });
    await this.reload();
  }

  // 点击"生成视频"：校验 Key，有已有视频时确认后生成
  onGenerateVideoClick() {
    this.runWithGuard(async () => {
      if (this.hasVideos) {
        const r = await promptAction.showDialog({
          title: '重新生成？',
          message: '当前已有视频，重新生成会覆盖现有内容。是否继续？',
          buttons: [
            { text: '取消', color: Theme.textSecondary },
            { text: '继续生成', color: Theme.primary }
          ]
        });
        if (r.index === 1) {
          this.doGenerateVideos();
        }
      } else {
        this.doGenerateVideos();
      }
    });
  }

  // 执行成片合成：调 UseCases.composeFinalVideo，提示结果后刷新数据
  async doComposeFinalVideo(): Promise<void> {
    this.busy = true;
    this.busyLabel = '合成成片中…';
    this.stageLabel = '合成成片';
    const settings = await SettingsStore.load();
    const result = await UseCases.composeFinalVideo(this.projectId, this.currentEpisodeId, settings);
    this.busy = false;
    this.clearProgress();
    promptAction.showToast({ message: result.ok ? '成片已生成' : `合成失败：${result.error}` });
    await this.reload();
  }

  // 点击"合成成片"：已有成片时弹二次确认；合成本身不需要 API Key
  onComposeFinalVideoClick() {
    if (this.hasFinalVideo) {
      promptAction.showDialog({
        title: '重新合成？',
        message: '当前已有成片，重新合成会覆盖成片结果。是否继续？',
        buttons: [
          { text: '取消', color: Theme.textSecondary },
          { text: '继续合成', color: Theme.primary }
        ]
      }).then((r) => {
        if (r.index === 1) {
          this.doComposeFinalVideo();
        }
      });
    } else {
      this.doComposeFinalVideo();
    }
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

  // ────────────── 集切换器（横向 chips：第 N 集 / ＋新增；长按删除） ──────────────

  // 确认新增剧集：标题与内容都为空时提示失败，否则创建并切换到新集
  private createEpisode(title: string, content: string): void {
    if (title.length === 0 && content.length === 0) {
      promptAction.showToast({ message: '标题和内容不能同时为空' });
      return;
    }
    UseCases.createEpisode(this.projectId, title, content).then(async (id) => {
      if (id > 0) {
        this.currentEpisodeId = id;
        promptAction.showToast({ message: '剧集已创建' });
        await this.reload();
      } else {
        promptAction.showToast({ message: '剧集创建失败' });
      }
    }).catch(() => {
      promptAction.showToast({ message: '剧集创建失败' });
    });
  }

  // 新增剧集：弹出输入对话框
  private showAddEpisodeDialog(): void {
    if (!this.addEpisodeDialog) {
      this.addEpisodeDialog = new CustomDialogController({
        builder: AddEpisodeDialog({
          onConfirm: (title: string, content: string) => this.createEpisode(title, content)
        }),
        autoCancel: true
      });
    }
    this.addEpisodeDialog.open();
  }

  // 长按删除单集：仅剩一集时提示不可删除，否则二次确认
  private confirmDeleteEpisode(episode: Episode): void {
    if (this.episodes.length <= 1) {
      promptAction.showToast({ message: '至少保留一集' });
      return;
    }
    promptAction.showDialog({
      title: '删除剧集？',
      message: `确定删除第 ${episode.episodeNumber} 集？该集的分镜、图片、视频与成片都会被清除。`,
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '删除', color: Theme.primary }
      ]
    }).then((r) => {
      if (r.index === 1) {
        this.deleteEpisode(episode);
      }
    });
  }

  // 执行删除单集：删除后 currentEpisodeId 置 0，由 reload 重新选定第一集
  private deleteEpisode(episode: Episode): void {
    UseCases.deleteEpisode(episode.id).then(async (ok) => {
      if (ok) {
        this.currentEpisodeId = 0;
        promptAction.showToast({ message: '剧集已删除' });
        await this.reload();
      } else {
        promptAction.showToast({ message: '剧集删除失败' });
      }
    }).catch(() => {
      promptAction.showToast({ message: '剧集删除失败' });
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

  // 清空阶段进度相关 state（在每次 do* 结束 / 异常路径上调用）
  private clearProgress(): void {
    this.stageLabel = '';
    this.progressCurrent = 0;
    this.progressTotal = 0;
    this.progressEntity = '';
  }

  // 阶段进度卡片：busy 时显示在项目信息下方。
  // 有 current/total 时显示「阶段 + 第 N/M 张 + 正在处理 X」；否则只显示阶段。
  @Builder
  ProgressCard() {
    Column() {
      Row() {
        // 阶段小圆点 + 阶段名
        Column() {
          Text('●')
            .fontSize(12)
            .fontColor(Theme.primary)
            .width(16)
            .textAlign(TextAlign.Center)
        }
        Text(this.stageLabel)
          .fontSize(15)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
        Blank().layoutWeight(1)
        // 当前/总数（仅在有进度时显示）
        if (this.progressTotal > 0) {
          Text(`第 ${this.progressCurrent}/${this.progressTotal} 张`)
            .fontSize(14)
            .fontColor(Theme.primary)
            .fontWeight(FontWeight.Bold)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 进度条（仅在有进度时显示）
      if (this.progressTotal > 0) {
        Progress({
          value: this.progressCurrent,
          total: this.progressTotal
        })
          .width('100%')
          .height(4)
          .color(Theme.primary)
          .backgroundColor(Theme.surfaceAlt)
          .margin({ top: 8 })
      }

      // 正在处理对象 + busy 详细标签
      if (this.progressEntity.length > 0) {
        Text(`正在处理：${this.progressEntity}`)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
          .width('100%')
          .margin({ top: 8 })
      } else {
        Text(this.busyLabel)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .backgroundColor(Theme.surface)
    .borderRadius(12)
    .border({ width: 1, color: Theme.primary })
    .margin({ bottom: 16 })
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
        Button('查看日志')
          .fontSize(13)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .padding({ left: 10, right: 10 })
          .margin({ right: 8 })
          .enabled(!this.busy)
          .opacity(this.busy ? 0.5 : 1)
          .onClick(() => {
            router.pushUrl({ url: 'pages/ApiLogPage' });
          })
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

            // 集切换器：第 N 集 chips（点击切换，长按删除）+ 新增 chip
            if (this.episodes.length > 0) {
              Scroll() {
                Row() {
                  ForEach(this.episodes, (ep: Episode) => {
                    Text(`第 ${ep.episodeNumber} 集`)
                      .fontSize(15)
                      .fontColor(ep.id === this.currentEpisodeId ? Color.White : Theme.primary)
                      .backgroundColor(ep.id === this.currentEpisodeId ? Theme.primary : Theme.surface)
                      .borderRadius(16)
                      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                      .margin({ right: 10 })
                      .onClick(() => {
                        if (ep.id !== this.currentEpisodeId) {
                          this.currentEpisodeId = ep.id;
                          this.reload();
                        }
                      })
                      .gesture(
                        LongPressGesture()
                          .onAction(() => {
                            this.confirmDeleteEpisode(ep);
                          })
                      )
                  }, (ep: Episode) => `${ep.id}`)
                  Text('＋ 新增')
                    .fontSize(15)
                    .fontColor(Theme.primary)
                    .backgroundColor(Theme.surface)
                    .fontWeight(FontWeight.Bold)
                    .borderRadius(16)
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .onClick(() => this.showAddEpisodeDialog())
                }
                .padding({ bottom: 8 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .margin({ bottom: 12 })
            }

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

            // 阶段进度卡片：仅在忙碌时显示
            if (this.busy && this.stageLabel.length > 0) {
              this.ProgressCard()
            }

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
                router.pushUrl({ url: 'pages/ScriptViewerPage', params: { projectId: this.projectId, episodeId: this.currentEpisodeId } });
              })
              .margin({ bottom: 10 })

            // Character operation buttons（放在分镜前面）
            Row() {
              Button(this.busy ? this.busyLabel : '提取角色')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy)
                .onClick(() => this.onExtractCharactersClick())
              Button('生成角色图')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy && this.hasCharacters)
                .margin({ left: 10 })
                .onClick(() => this.onGenerateCharacterImagesClick())
            }
            .width('100%')
            .margin({ bottom: 10 })

            // Character count display
            if (this.characters.length > 0) {
              Text(`已提取 ${this.characters.length} 个角色`)
                .fontSize(14)
                .fontColor(Theme.textSecondary)
                .width('100%')
                .margin({ bottom: 10 })
            }

            // View Characters button
            Button('查看角色')
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor(Theme.textPrimary)
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(10)
              .enabled(this.hasCharacters)
              .opacity(this.hasCharacters ? 1 : 0.5)
              .onClick(() => {
                router.pushUrl({ url: 'pages/CharacterListPage', params: { projectId: this.projectId } });
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
                  router.pushUrl({ url: 'pages/StoryboardImagePage', params: { projectId: this.projectId, episodeId: this.currentEpisodeId } });
                })
            }
            .width('100%')
            .margin({ bottom: 24 })

            // Video generation button row
            Row() {
              Button(this.busy ? this.busyLabel : '生成视频')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy)
                .onClick(() => this.onGenerateVideoClick())
              Button('查看视频')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Theme.textPrimary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(10)
                .enabled(!this.busy && this.hasVideos)
                .opacity(this.hasVideos ? 1 : 0.5)
                .margin({ left: 10 })
                .onClick(() => {
                  router.pushUrl({ url: 'pages/VideoViewerPage', params: { projectId: this.projectId, episodeId: this.currentEpisodeId } });
                })
            }
            .width('100%')
            .margin({ bottom: 24 })

            // Final video button row
            Row() {
              Button(this.busy ? this.busyLabel : '合成成片')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.busy ? Theme.primaryDisabled : Theme.primary)
                .borderRadius(10)
                .enabled(!this.busy)
                .onClick(() => this.onComposeFinalVideoClick())
              Button('播放成片')
                .layoutWeight(1)
                .height(46)
                .fontSize(14)
                .fontColor(Theme.textPrimary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(10)
                .enabled(!this.busy && this.hasFinalVideo)
                .opacity(this.hasFinalVideo ? 1 : 0.5)
                .margin({ left: 10 })
                .onClick(() => {
                  router.pushUrl({ url: 'pages/FinalVideoPage', params: { projectId: this.projectId, episodeId: this.currentEpisodeId } });
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
