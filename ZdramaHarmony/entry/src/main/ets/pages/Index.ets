import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { DramaProject } from '../model/DramaModels';
import { Theme, statusLabel, stageLabel } from '../common/Theme';

@Entry
@Component
struct Index {
  @State projects: DramaProject[] = [];
  @State loading: boolean = true;

  onPageShow(): void {
    this.loadProjects();
  }

  async loadProjects(): Promise<void> {
    this.loading = true;
    try {
      this.projects = await UseCases.getProjects();
    } catch (e) {
      promptAction.showToast({ message: '加载项目失败' });
    } finally {
      this.loading = false;
    }
  }

  confirmDelete(project: DramaProject): void {
    promptAction.showDialog({
      title: '删除项目？',
      message: `删除项目「${project.title}」？这会一并清除剧集与脚本。`,
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '删除', color: Theme.primary }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        const ok = await UseCases.deleteProject(project.id);
        promptAction.showToast({ message: ok ? '项目已删除' : '删除失败' });
        if (ok) {
          this.loadProjects();
        }
      }
    });
  }

  @Builder
  ProjectCard(project: DramaProject) {
    Column() {
      Text(project.title)
        .fontSize(18)
        .fontColor(Theme.textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row() {
        Text(statusLabel(project.status))
          .fontSize(13)
          .fontColor(Theme.primary)
        Text(`  ·  阶段：${stageLabel(project.currentStage)}`)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
        Text(`  ·  ${project.shotCount} 镜`)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
      }
      .width('100%')
      .margin({ top: 6 })

      Text(project.prompt)
        .fontSize(13)
        .fontColor(Theme.textHint)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .backgroundColor(Theme.surface)
    .borderRadius(12)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ProjectDetailPage', params: { projectId: project.id } });
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.confirmDelete(project);
        })
    )
  }

  build() {
    Column() {
      // Top bar
      Row() {
        Text('项目列表')
          .fontSize(22)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button('设置')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick(() => router.pushUrl({ url: 'pages/SettingsPage' }))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Text('长按项目可删除')
        .fontSize(12)
        .fontColor(Theme.textHint)
        .width('100%')
        .padding({ left: 16, bottom: 8 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(48).height(48).color(Theme.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else if (this.projects.length === 0) {
        Column() {
          Text('暂无项目')
            .fontSize(16)
            .fontColor(Theme.textHint)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        List({ space: 12 }) {
          ForEach(this.projects, (project: DramaProject) => {
            ListItem() {
              this.ProjectCard(project)
            }
          }, (project: DramaProject) => project.id.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
      }

      // Create button
      Column() {
        Button('创建项目')
          .width('100%')
          .height(50)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(Theme.primary)
          .borderRadius(12)
          .onClick(() => router.pushUrl({ url: 'pages/CreateProjectPage' }))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
