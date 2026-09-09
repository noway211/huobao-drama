import { router, promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UseCases } from '../usecase/UseCases';
import { AssetStatus, DramaProject } from '../model/DramaModels';
import { Theme } from '../common/Theme';
import { AlbumSaver } from '../service/AlbumSaver';

interface FinalVideoPageParams {
  projectId: number;
  episodeId?: number;
}

/**
 * 成片播放页 — 播放项目合成后的 final_video.mp4。
 * 移植自 Android 的 StoryboardFinalVideoActivity。
 */
@Entry
@Component
struct FinalVideoPage {
  @State title: string = '';
  @State videoSrc: string = '';
  @State loading: boolean = true;
  @State errorText: string = '';
  @State fullScreen: boolean = false;
  @State saving: boolean = false;
  // SaveButton 安全控件配置：系统自动校验真实用户点击后才下发写权限
  private saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_FILE,
    buttonType: ButtonType.Capsule
  };

  private projectId: number = 0;
  private episodeId: number = 0;

  // 组件即将出现：从路由参数中读取项目 ID 与剧集 ID（后者缺省时回退项目级成片）
  aboutToAppear(): void {
    const params = router.getParams() as FinalVideoPageParams;
    if (!params || !params.projectId) {
      this.errorText = '缺少项目 ID';
      this.loading = false;
      return;
    }
    this.projectId = params.projectId;
    if (params.episodeId) {
      this.episodeId = params.episodeId;
    }
    this.loadFinalVideo();
  }

  private async loadFinalVideo(): Promise<void> {
    try {
      const project = await UseCases.getProject(this.projectId);
      if (!project) {
        this.errorText = '项目不存在';
        return;
      }
      this.title = project.title;
      // 多集下读当前集成片；episodeId 缺省时回退项目级字段（旧数据兼容）
      const episode = this.episodeId > 0 ? await UseCases.getEpisodeById(this.episodeId) : null;
      const localPath = episode
        ? (episode.finalVideoLocalPath ?? project.finalVideoLocalPath)
        : project.finalVideoLocalPath;
      if (!localPath || localPath.length === 0) {
        this.errorText = '成片视频不存在';
        return;
      }
      this.videoSrc = localPath.startsWith('file://')
        ? localPath
        : `file://${localPath}`;
    } catch (e) {
      this.errorText = `加载成片失败：${(e as Error).message ?? String(e)}`;
    } finally {
      this.loading = false;
    }
  }

  // 二次确认 → 软删除(状态置 PENDING、清字段) + 容错删本地文件 + 重新 load
  private async onDeleteFinalVideoClick(): Promise<void> {
    promptAction.showDialog({
      title: '删除成片？',
      message: '删除后需要重新合成。可在项目详情重新合成成片。',
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '删除', color: Theme.primary }
      ]
    }).then(async (r) => {
      if (r.index !== 1) {
        return;
      }
      // 多集：走剧集级删除（内部完成 unlink + 置 PENDING）
      if (this.episodeId > 0) {
        try {
          const ok = await UseCases.deleteEpisodeFinalVideo(this.episodeId);
          if (!ok) {
            promptAction.showToast({ message: '删除失败: 剧集不存在' });
            return;
          }
        } catch (e) {
          promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
          return;
        }
        promptAction.showToast({ message: '已删除' });
        await this.loadFinalVideo();
        return;
      }
      // 兼容旧路径：重新读取项目以拿到当前 status / currentStage / finalVideoLocalPath
      let project: DramaProject | null = null;
      try {
        project = await UseCases.getProject(this.projectId);
      } catch (e) {
        promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
        return;
      }
      if (!project) {
        promptAction.showToast({ message: '删除失败: 项目不存在' });
        return;
      }
      const localPath = project.finalVideoLocalPath ?? '';
      let ok: boolean = false;
      try {
        ok = await UseCases.updateProjectFinalVideo(
          this.projectId, project.status, project.currentStage,
          AssetStatus.PENDING, null, null, null
        );
      } catch (e) {
        promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
        return;
      }
      if (!ok) {
        promptAction.showToast({ message: '删除失败: 数据库更新未生效' });
        return;
      }
      if (localPath) {
        try {
          fileIo.unlinkSync(localPath);
        } catch (e) {
          hilog.warn(1, "DeleteFinalVideo", "unlink failed: %{public}s", (e as Error).message);
        }
      }
      promptAction.showToast({ message: '已删除' });
      await this.loadFinalVideo();
    });
  }

  // SaveButton 安全控件回调：系统已校验用户真实点击，自动授予写权限
  private async onSaveToAlbumSaveClick(): Promise<void> {
    if (this.saving) {
      return;
    }
    // 取沙盒内绝对路径（去 file:// 前缀）
    const localPath: string = this.videoSrc.startsWith('file://')
      ? this.videoSrc.substring('file://'.length)
      : this.videoSrc;
    if (localPath.length === 0) {
      promptAction.showToast({ message: '保存失败：成片路径为空' });
      return;
    }
    this.saving = true;
    try {
      const result = await AlbumSaver.saveVideo(localPath, this.title);
      if (result.ok) {
        promptAction.showToast({ message: '已保存到相册' });
        hilog.info(1, "SaveToAlbum", "save ok uri=%{public}s", result.uri);
      } else {
        promptAction.showToast({ message: `保存失败：${result.error}` });
        hilog.error(1, "SaveToAlbum", "save failed: %{public}s", result.error);
      }
    } finally {
      this.saving = false;
    }
  }

  onBackPress(): boolean {
    if (this.fullScreen) {
      this.fullScreen = false;
      return true;
    }
    return false;
  }

  build(): void {
    Stack() {
      Column() {
        Row() {
          Button('返回')
            .fontSize(14)
            .backgroundColor(Theme.surfaceAlt)
            .fontColor(Theme.textPrimary)
            .height(36)
            .onClick((): void => {
              if (this.fullScreen) {
                this.fullScreen = false;
              } else {
                router.back();
              }
            })
          Text(`${this.title} · 成片`)
            .fontSize(18)
            .fontColor(Theme.textPrimary)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 12 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Theme.primary)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else if (this.errorText.length > 0) {
          Column() {
            Text(this.errorText)
              .fontSize(16)
              .fontColor(Theme.textSecondary)
              .margin({ bottom: 12 })
            Button('返回项目详情')
              .fontSize(14)
              .backgroundColor(Theme.primary)
              .fontColor(Color.White)
              .height(40)
              .onClick((): void => router.back())
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
        } else {
          Column() {
            Video({ src: this.videoSrc, currentProgressRate: 1.0 })
              .width('100%')
              .height(240)
              .controls(true)
              .autoPlay(false)
              .loop(false)
              .objectFit(ImageFit.Contain)
              .borderRadius(10)
              .backgroundColor(Theme.surfaceAlt)
              .onClick((): void => {
                this.fullScreen = true;
              })
              .onError((): void => {
                promptAction.showToast({ message: '成片播放出错' });
              })

            Text('点击视频进入全屏播放')
              .fontSize(12)
              .fontColor(Theme.textSecondary)
              .margin({ top: 8 })
              .width('100%')
              .textAlign(TextAlign.Center)

            // 操作按钮行（左：保存到相册 / 右：删除）
            Row() {
              // 保存到相册 — SaveButton 安全控件（系统自动校验真实点击后下发写权限）
              SaveButton(this.saveButtonOptions)
                .fontSize(13)
                .backgroundColor(Theme.primary)
                .fontColor(Color.White)
                .height(32)
                .padding({ left: 12, right: 12 })
                .onClick(async (_event: ClickEvent, result: SaveButtonOnClickResult) => {
                  if (result === SaveButtonOnClickResult.SUCCESS) {
                    await this.onSaveToAlbumSaveClick();
                  } else {
                    hilog.warn(1, "SaveToAlbum", "SaveButton result not SUCCESS: %{public}d", result);
                    promptAction.showToast({ message: '设置权限失败' });
                  }
                })
              Blank().layoutWeight(1)
              Button('删除')
                .fontSize(13)
                .backgroundColor(Theme.surfaceAlt)
                .fontColor(Theme.textPrimary)
                .height(32)
                .padding({ left: 12, right: 12 })
                .onClick((): void => { this.onDeleteFinalVideoClick() })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .padding(16)
          .width('100%')
          .backgroundColor(Theme.surface)
          .borderRadius(12)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(Theme.bg)

      if (this.fullScreen && this.videoSrc.length > 0) {
        Column() {
          Row() {
            Text(`${this.title} · 成片`)
              .fontSize(16)
              .fontColor(Color.White)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('关闭')
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.fullScreen = false;
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 12 })

          Video({ src: this.videoSrc, currentProgressRate: 1.0 })
            .width('100%')
            .layoutWeight(1)
            .controls(true)
            .autoPlay(true)
            .objectFit(ImageFit.Contain)
            .onError((): void => {
              promptAction.showToast({ message: '成片播放失败' });
              this.fullScreen = false;
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5000000')
        .position({ x: 0, y: 0 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
