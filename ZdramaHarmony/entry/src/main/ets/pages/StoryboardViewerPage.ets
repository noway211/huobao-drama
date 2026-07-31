import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot } from '../model/DramaModels';
import { Theme } from '../common/Theme';

interface ViewerParams {
  projectId: number;
}

// 编辑图片提示词的弹层内边距
const DIALOG_PADDING = 24;

@Entry
@Component
struct StoryboardViewerPage {
  @State title: string = '';
  @State shots: StoryboardShot[] = [];
  @State loading: boolean = true;
  @State shotCountText: string = '';
  @State editingShot: StoryboardShot | null = null;
  @State editText: string = '';
  private projectId: number = 0;

  // 组件即将出现：从路由参数中读取项目 ID
  aboutToAppear(): void {
    const params = router.getParams() as ViewerParams;
    if (params && params.projectId) {
      this.projectId = params.projectId;
    }
  }

  // 页面显示时加载分镜数据，无分镜时提示后返回
  async onPageShow(): Promise<void> {
    this.loading = true;
    const project = await UseCases.getProject(this.projectId);
    this.title = project?.title ?? '分镜';
    const storyboards = await UseCases.getStoryboards(this.projectId);
    if (storyboards.length === 0) {
      promptAction.showToast({ message: '暂无分镜' });
      router.back();
      return;
    }
    this.shots = storyboards;
    this.shotCountText = `共 ${storyboards.length} 个分镜`;
    this.loading = false;
  }

  // 打开编辑图片提示词弹层
  private startEditing(shot: StoryboardShot): void {
    this.editText = shot.imagePrompt;
    this.editingShot = shot;
  }

  // 保存编辑后的图片提示词，关闭弹层并刷新数据
  private async saveEdit(): Promise<void> {
    const shot = this.editingShot;
    if (!shot || this.editText.trim().length === 0) {
      this.editingShot = null;
      return;
    }
    if (this.editText === shot.imagePrompt) {
      // 未修改直接关闭
      this.editingShot = null;
      return;
    }
    this.editingShot = null;
    try {
      await UseCases.updateShotPrompt(shot.id, this.editText.trim());
      promptAction.showToast({ message: `#${shot.shotNumber} 图片提示词已更新` });
    } catch (e) {
      promptAction.showToast({ message: '保存失败，请重试' });
    }
    // 刷新分镜数据
    this.shots = await UseCases.getStoryboards(this.projectId);
  }

  // 取消编辑
  cancelEdit(): void {
    this.editingShot = null;
  }

  // 格式化单个分镜的展示文本（添加行号标识，便于点击编辑）
  formatShot(shot: StoryboardShot): string {
    let text = `#${shot.shotNumber}  ${shot.scene}\n`;
    text += `动作：${shot.action}\n`;
    text += `对白：${shot.dialogue}\n`;
    text += `镜头：${shot.camera}\n`;
    text += `时长：${shot.durationSeconds} 秒\n`;
    text += `视频提示词：${shot.videoPrompt}`;
    // 如有错误信息也展示
    if (shot.imageErrorMessage) {
      text += `\n图片错误：${shot.imageErrorMessage}`;
    }
    if (shot.videoErrorMessage) {
      text += `\n视频错误：${shot.videoErrorMessage}`;
    }
    return text;
  }

  build() {
    Column() {
      // 返回栏
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick(() => router.back())
        Text(this.title)
          .fontSize(18)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 12 })
        Text(this.shotCountText)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(48).height(48).color(Theme.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        List({ space: 12 }) {
          ForEach(this.shots, (shot: StoryboardShot) => {
            ListItem() {
              Column() {
                // 分镜标题
                Text(`#${shot.shotNumber}  ${shot.scene}`)
                  .fontSize(16)
                  .fontColor(Theme.textPrimary)
                  .fontWeight(FontWeight.Bold)
                  .width('100%')
                  .margin({ bottom: 10 })

                // 图片提示词行（可点击编辑）
                Column() {
                  Text('图片提示词：')
                    .fontSize(13)
                    .fontColor(Theme.textSecondary)
                    .margin({ bottom: 4 })
                  Text(shot.imagePrompt)
                    .fontSize(14)
                    .fontColor(Theme.textPrimary)
                    .lineHeight(20)
                    .width('100%')
                  Row() {
                    Text('点击编辑')
                      .fontSize(12)
                      .fontColor(Theme.primary)
                  }
                  .width('100%')
                  .margin({ top: 6 })
                  .onClick((): void => {
                    this.startEditing(shot);
                  })
                }
                .padding(12)
                .width('100%')
                .backgroundColor('#1A000000')
                .borderRadius(8)
                .margin({ bottom: 10 })

                // 其余分镜信息
                Text(this.formatShot(shot))
                  .fontSize(13)
                  .fontColor(Theme.textSecondary)
                  .lineHeight(20)
                  .width('100%')
              }
              .padding(16)
              .width('100%')
              .backgroundColor(Theme.surface)
              .borderRadius(10)
            }
          }, (shot: StoryboardShot) => shot.id > 0 ? shot.id.toString() : shot.shotNumber.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
        .scrollBar(BarState.Off)
      }

      // ── 编辑图片提示词弹层 ──
      if (this.editingShot) {
        Column() {
          // 遮罩半透明层，点击可关闭
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')
            .onClick(() => this.cancelEdit())
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })

        // 中间对话框
        Column() {
          Column() {
            Text(`编辑 #${this.editingShot.shotNumber} 图片提示词`)
              .fontSize(18)
              .fontColor(Theme.textPrimary)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .margin({ bottom: 16 })

            TextArea({ text: this.editText, placeholder: '输入新的图片提示词…' })
              .height(180)
              .backgroundColor(Color.White)
              .borderRadius(8)
              .padding(12)
              .fontSize(14)
              .onChange((v: string): void => {
                this.editText = v;
              })

            Row() {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .fontSize(14)
                .fontColor(Theme.textSecondary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(10)
                .onClick(() => {
                  this.cancelEdit();
                })
              Button('保存')
                .layoutWeight(1)
                .height(44)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(Theme.primary)
                .borderRadius(10)
                .margin({ left: 12 })
                .onClick(() => {
                  this.saveEdit();
                })
            }
            .width('100%')
            .margin({ top: 16 })
          }
          .padding(DIALOG_PADDING)
          .width('85%')
          .backgroundColor(Theme.surface)
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}