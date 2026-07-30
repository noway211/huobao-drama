import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { Theme } from '../common/Theme';

interface ViewerParams {
  projectId: number;
}

@Entry
@Component
struct ScriptViewerPage {
  @State title: string = '';
  @State script: string = '';
  @State loading: boolean = true;
  private projectId: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as ViewerParams;
    if (params && params.projectId) {
      this.projectId = params.projectId;
    }
  }

  async onPageShow(): Promise<void> {
    this.loading = true;
    const project = await UseCases.getProject(this.projectId);
    const episode = await UseCases.getEpisode(this.projectId);
    this.title = project?.title ?? '脚本';

    // Prefer episode.scriptContent, fall back to project.generatedScript.
    const fromEpisode = episode?.scriptContent;
    const fromProject = project?.generatedScript;
    const content = (fromEpisode && fromEpisode.trim().length > 0)
      ? fromEpisode
      : (fromProject ?? '');
    this.script = content;
    this.loading = false;

    if (content.trim().length === 0) {
      promptAction.showToast({ message: '暂无脚本内容' });
    }
  }

  build() {
    Column() {
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
        Scroll() {
          Text(this.script)
            .fontSize(15)
            .fontColor(Theme.textPrimary)
            .lineHeight(24)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .padding({ left: 16, right: 16, bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
