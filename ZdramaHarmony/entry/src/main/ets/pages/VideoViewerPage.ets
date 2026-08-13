import { router, promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, AssetStatus } from '../model/DramaModels';
import { Theme } from '../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface VideoPageParams {
  projectId: number;
}

/**
 * 视频查看页面 — 展示分镜已生成的视频列表。
 * 每个分镜一屏，支持左右滑动浏览；点击视频进入全屏播放。
 * 移植自 Android StoryboardVideoActivity 的 MVP 功能。
 */
@Entry
@Component
struct VideoViewerPage {
  @State title: string = '';
  @State shots: StoryboardShot[] = [];
  @State loading: boolean = true;
  @State summaryText: string = '';
  @State fullScreenSrc: string = '';
  @State fullScreenLabel: string = '';

  private projectId: number = 0;

  // 组件即将出现：从路由参数中读取项目 ID
  aboutToAppear(): void {
    const params = router.getParams() as VideoPageParams;
    if (params && params.projectId) {
      this.projectId = params.projectId;
    }
  }

  // 页面每次显示时重新加载数据
  async onPageShow(): Promise<void> {
    this.loading = true;
    const project = await UseCases.getProject(this.projectId);
    this.title = project?.title ?? '视频查看';
    const all = await UseCases.getStoryboards(this.projectId);

    const completed: StoryboardShot[] = [];
    for (const s of all) {
      if (s.videoStatus === AssetStatus.COMPLETED) {
        completed.push(s);
      }
    }
    this.shots = completed;
    this.summaryText = `共 ${completed.length}/${all.length} 个视频`;
    this.loading = false;
  }

  onBackPress(): boolean | void {
    if (this.fullScreenSrc.length > 0) {
      this.fullScreenSrc = '';
      this.fullScreenLabel = '';
      return true;
    }
  }

  // 获取视频源：优先本地路径，回退到远程 URL
  private videoSrc(shot: StoryboardShot): string {
    if (shot.videoLocalPath) {
      return `file://${shot.videoLocalPath}`;
    }
    if (shot.videoUrl) {
      return shot.videoUrl;
    }
    return '';
  }

  // 格式化分镜描述（动作 + 镜头的摘要）
  private shotMeta(shot: StoryboardShot): string {
    let text = '';
    if (shot.action) {
      text += `${shot.action}`;
    }
    if (shot.camera) {
      text += text.length > 0 ? ' · ' : '';
      text += shot.camera;
    }
    if (shot.videoErrorMessage) {
      text += '\n错误：' + shot.videoErrorMessage;
    }
    return text;
  }

  // 二次确认 → 软删除(状态置 PENDING、清字段,含 videoTaskId) + 容错删本地文件 + 重新 load
  private async onDeleteVideoClick(shot: StoryboardShot): Promise<void> {
    promptAction.showDialog({
      title: '删除视频？',
      message: '删除后需要重新生成。可在分镜列表重新生成视频。',
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '删除', color: Theme.primary }
      ]
    }).then(async (r) => {
      if (r.index !== 1) {
        return;
      }
      try {
        await UseCases.updateShotVideo(
          shot.id, AssetStatus.PENDING, null, null, null, null
        );
      } catch (e) {
        promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
        return;
      }
      if (shot.videoLocalPath) {
        try {
          fileIo.unlinkSync(shot.videoLocalPath);
        } catch (e) {
          hilog.warn(1, "DeleteVideo", "unlink failed: %{public}s", (e as Error).message);
        }
      }
      promptAction.showToast({ message: '已删除' });
      await this.onPageShow();
    });
  }

  build(): void {
    Column() {
      // ── 顶部栏 ──
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick((): void => {
            if (this.fullScreenSrc.length > 0) {
              this.fullScreenSrc = '';
              this.fullScreenLabel = '';
            } else {
              router.back();
            }
          })
        Text(this.title)
          .fontSize(18)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 12 })
        Text(this.summaryText)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      // ── 加载中 ──
      if (this.loading) {
        Column() {
          LoadingProgress().width(48).height(48).color(Theme.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else if (this.shots.length === 0) {
        // ── 空态 ──
        Column() {
          Text('暂无已生成的视频')
            .fontSize(16)
            .fontColor(Theme.textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        // ── 视频列表 ──
        Scroll() {
          Column() {
            ForEach(this.shots, (shot: StoryboardShot) => {
              Column() {
                // 分镜编号与场景
                Text(`#${shot.shotNumber}  ${shot.scene}`)
                  .fontSize(15)
                  .fontColor(Theme.textPrimary)
                  .fontWeight(FontWeight.Bold)
                  .width('100%')
                  .margin({ bottom: 8 })

                // 视频播放器（带控制条，不自动播放）
                Video({ src: this.videoSrc(shot), previewUri: undefined, currentProgressRate: 1.0 })
                  .width('100%')
                  .height(240)
                  .controls(true)
                  .autoPlay(false)
                  .loop(false)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(10)
                  .backgroundColor(Theme.surfaceAlt)
                  .onClick((): void => {
                    this.fullScreenSrc = this.videoSrc(shot);
                    this.fullScreenLabel = `#${shot.shotNumber}  ${shot.scene}`;
                  })
                  .onError(() => {
                    promptAction.showToast({ message: `#${shot.shotNumber} 视频播放出错` });
                  })

                // 视频描述
                if (this.shotMeta(shot).length > 0) {
                  Text(this.shotMeta(shot))
                    .fontSize(13)
                    .fontColor(Theme.textSecondary)
                    .lineHeight(18)
                    .width('100%')
                    .margin({ top: 6 })
                }

                // 时长标识
                Text(`⏱ ${shot.durationSeconds}s`)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary)
                  .width('100%')
                  .margin({ top: 4 })

                // 删除按钮(右下角)
                Row() {
                  Blank().layoutWeight(1)
                  Button('删除')
                    .fontSize(13)
                    .backgroundColor(Theme.surfaceAlt)
                    .fontColor(Theme.textPrimary)
                    .height(32)
                    .padding({ left: 12, right: 12 })
                    .onClick((): void => { this.onDeleteVideoClick(shot) })
                }
                .width('100%')
                .margin({ top: 8 })
              }
              .padding(12)
              .width('100%')
              .backgroundColor(Theme.surface)
              .borderRadius(12)
              .margin({ bottom: 16 })
            }, (shot: StoryboardShot): string => {
              return shot.id > 0 ? shot.id.toString() : shot.shotNumber.toString();
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
      }

      // ── 全屏播放弹层 ──
      if (this.fullScreenSrc.length > 0) {
        Column() {
          // 顶部关闭栏
          Row() {
            Text(this.fullScreenLabel)
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
                this.fullScreenSrc = '';
                this.fullScreenLabel = '';
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 12 })

          // 全屏视频播放
          Video({ src: this.fullScreenSrc, currentProgressRate: 1.0 })
            .width('100%')
            .layoutWeight(1)
            .controls(true)
            .autoPlay(true)
            .objectFit(ImageFit.Contain)
            .onError(() => {
              promptAction.showToast({ message: '视频播放失败' });
              this.fullScreenSrc = '';
              this.fullScreenLabel = '';
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
    .backgroundColor(Theme.bg)
  }
}