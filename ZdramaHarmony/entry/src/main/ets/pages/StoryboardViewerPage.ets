import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot } from '../model/DramaModels';
import { Theme } from '../common/Theme';

interface ViewerParams {
  projectId: number;
}

@Entry
@Component
struct StoryboardViewerPage {
  @State title: string = '';
  @State shots: StoryboardShot[] = [];
  @State loading: boolean = true;
  @State shotCountText: string = '';
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

  // 格式化单个分镜的展示文本
  formatShot(shot: StoryboardShot): string {
    let text = `#${shot.shotNumber}  ${shot.scene}\n`;
    text += `动作：${shot.action}\n`;
    text += `对白：${shot.dialogue}\n`;
    text += `镜头：${shot.camera}\n`;
    text += `时长：${shot.durationSeconds} 秒\n`;
    text += `图片提示词：${shot.imagePrompt}\n`;
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
                Text(this.formatShot(shot))
                  .fontSize(14)
                  .fontColor(Theme.textPrimary)
                  .lineHeight(22)
                  .width('100%')
                  .textAlign(TextAlign.Start)
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}