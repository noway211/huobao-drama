import { router, promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, AssetStatus } from '../model/DramaModels';
import { Theme } from '../common/Theme';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface ImagePageParams {
  projectId: number;
}

// 全屏预览手势状态缩放因子取值范围
const MIN_SCALE = 0.5;
const MAX_SCALE = 10;

/**
 * 图片查看页面 — 展示分镜已生成的图片。
 * 支持全屏双手指捏合缩放、双手指旋转、单指拖动平移。
 * 移植自 Android StoryboardImageActivity 的 MVP 功能。
 */
@Entry
@Component
struct StoryboardImagePage {
  @State title: string = '';
  @State shots: StoryboardShot[] = [];
  @State loading: boolean = true;
  @State summaryText: string = '';
  @State fullScreenSrc: string = '';
  @State fullScreenLabel: string = '';
  @State fullScale: number = 1;        // 当前缩放倍率
  @State fullRotation: number = 0;     // 当前旋转角度
  @State fullOffsetX: number = 0;      // 当前 X 偏移
  @State fullOffsetY: number = 0;      // 当前 Y 偏移

  // 手势基线（记录每次手势开始时当前值，用于计算增量）
  private baseScale: number = 1;
  private baseRotation: number = 0;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;
  private projectId: number = 0;

  // 组件即将出现：从路由参数中读取项目 ID
  aboutToAppear(): void {
    const params = router.getParams() as ImagePageParams;
    if (params && params.projectId) {
      this.projectId = params.projectId;
    }
  }

  // 页面每次显示时重新加载数据
  async onPageShow(): Promise<void> {
    this.loading = true;
    const project = await UseCases.getProject(this.projectId);
    this.title = project?.title ?? '图片查看';
    const all = await UseCases.getStoryboards(this.projectId);

    const completed: StoryboardShot[] = [];
    for (const s of all) {
      if (s.imageStatus === AssetStatus.COMPLETED) {
        completed.push(s);
      }
    }
    this.shots = completed;
    this.summaryText = `共 ${completed.length}/${all.length} 张`;
    this.loading = false;
  }

  onBackPress(): boolean | void {
    if (this.fullScreenSrc.length > 0) {
      hilog.info(1, "StoryboardImagePage", "imagepath %{public}s", this.fullScreenSrc)
      this.fullScreenSrc = '';
      this.fullScreenLabel = '';
      return true
    }
  }

  // 进入全屏时重置手势变换
  private openFullscreen(src: string, label: string): void {
    this.fullScreenSrc = src;
    this.fullScreenLabel = label;
    this.fullScale = 1;
    this.fullRotation = 0;
    this.fullOffsetX = 0;
    this.fullOffsetY = 0;
  }

  // 二次确认 → 软删除(状态置 PENDING、清字段) + 容错删本地文件 + 重新 load
  private async onDeleteImageClick(shot: StoryboardShot): Promise<void> {
    promptAction.showDialog({
      title: '删除图片？',
      message: '删除后需要重新生成。可在分镜列表重新生成图片。',
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '删除', color: Theme.primary }
      ]
    }).then(async (r) => {
      if (r.index !== 1) {
        return;
      }
      try {
        await UseCases.updateShotImage(
          shot.id, AssetStatus.PENDING, null, null, null
        );
      } catch (e) {
        promptAction.showToast({ message: '删除失败:' + ((e as Error).message ?? String(e)) });
        return;
      }
      if (shot.imageLocalPath && shot.imageLocalPath.length > 0) {
        try {
          fileIo.unlinkSync(shot.imageLocalPath);
        } catch (e) {
          hilog.warn(1, "DeleteImage", "unlink failed: %{public}s", (e as Error).message);
        }
      }
      promptAction.showToast({ message: '已删除' });
      await this.onPageShow();
    });
  }

  // 获取图片源：优先本地路径，回退到远程 URL
  private imgSrc(shot: StoryboardShot): string {
    if (shot.imageLocalPath) {
      return `file://${shot.imageLocalPath}`;
    }
    if (shot.imageUrl) {
      return shot.imageUrl;
    }
    return '';
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
          Text('暂无已生成的图片')
            .fontSize(16)
            .fontColor(Theme.textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        // ── 图片列表 ──
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

                // 图片
                Image(this.imgSrc(shot))
                  .width('100%')
                  .height(220)
                  .objectFit(ImageFit.Contain)
                  .backgroundColor(Theme.surfaceAlt)
                  .borderRadius(10)
                  .onClick((): void => {
                    this.openFullscreen(this.imgSrc(shot), `#${shot.shotNumber}  ${shot.scene}`);
                  })

                // 动作描述
                if (shot.action.length > 0) {
                  Text(shot.action)
                    .fontSize(13)
                    .fontColor(Theme.textSecondary)
                    .width('100%')
                    .lineHeight(18)
                    .margin({ top: 6 })
                }

                // 删除按钮(右下角)
                Row() {
                  Blank().layoutWeight(1)
                  Button('删除')
                    .fontSize(13)
                    .backgroundColor(Theme.surfaceAlt)
                    .fontColor(Theme.textPrimary)
                    .height(32)
                    .padding({ left: 12, right: 12 })
                    .onClick((): void => { this.onDeleteImageClick(shot) })
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

      // ── 全屏预览弹层 ──
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

          // 大图（支持双手指捏合缩放、旋转、单指拖动；点击关闭）
          Image(this.fullScreenSrc)
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
            .scale({ x: this.fullScale, y: this.fullScale })
            .rotate({ angle: this.fullRotation })
            .offset({ x: this.fullOffsetX, y: this.fullOffsetY })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture({ fingers: 2 })
                  .onActionStart((): void => {
                    this.baseScale = this.fullScale;
                  })
                  .onActionUpdate((event: GestureEvent): void => {
                    this.fullScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE,
                      this.baseScale * event.scale));
                  }),
                RotationGesture({ fingers: 2 })
                  .onActionStart((): void => {
                    this.baseRotation = this.fullRotation;
                  })
                  .onActionUpdate((event: GestureEvent): void => {
                    this.fullRotation = this.baseRotation + event.angle;
                  }),
                PanGesture({ fingers: 1 })
                  .onActionStart((): void => {
                    this.baseOffsetX = this.fullOffsetX;
                    this.baseOffsetY = this.fullOffsetY;
                  })
                  .onActionUpdate((event: GestureEvent): void => {
                    this.fullOffsetX = this.baseOffsetX + event.offsetX;
                    this.fullOffsetY = this.baseOffsetY + event.offsetY;
                  })
              )
            )
            .onClick((): void => {
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