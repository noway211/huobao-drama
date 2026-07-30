import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { CreateDramaInput } from '../model/DramaModels';
import { Theme } from '../common/Theme';

@Entry
@Component
struct CreateProjectPage {
  @State title: string = '';
  @State prompt: string = '';
  @State style: string = '现代短剧';
  @State audience: string = '大众受众';
  @State aspectRatioStr: string = '9:16';
  @State shotCount: string = '8';
  @State duration: string = '5';
  @State saving: boolean = false;

  // 校验输入并创建项目草稿，成功后跳转到项目详情页
  async save(): Promise<void> {
    const title = this.title.trim();
    const prompt = this.prompt.trim();
    if (title.length === 0 || prompt.length === 0) {
      promptAction.showToast({ message: '标题和故事提示词不能为空' });
      return;
    }
    const shots = parseInt(this.shotCount, 10);
    const dur = parseInt(this.duration, 10);
    if (!(shots > 0) || !(dur > 0)) {
      promptAction.showToast({ message: '分镜数量和时长必须是正数' });
      return;
    }

    const input: CreateDramaInput = {
      title: title,
      prompt: prompt,
      style: this.style.trim().length > 0 ? this.style.trim() : '现代短剧',
      targetAudience: this.audience.trim().length > 0 ? this.audience.trim() : '大众受众',
      aspectRatio: this.aspectRatioStr.trim().length > 0 ? this.aspectRatioStr.trim() : '9:16',
      shotCount: shots,
      shotDurationSeconds: dur
    };

    this.saving = true;
    try {
      const projectId = await UseCases.createDrama(input);
      promptAction.showToast({ message: '草稿已保存' });
      router.replaceUrl({ url: 'pages/ProjectDetailPage', params: { projectId: projectId } });
    } catch (e) {
      this.saving = false;
      promptAction.showToast({ message: '草稿保存失败' });
    }
  }

  // 通用带标签的表单项：根据 multiline 渲染多行文本域或单行输入框
  @Builder
  Field(label: string, value: string, onChange: (v: string) => void, placeholder: string, multiline: boolean) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor(Theme.textSecondary)
        .width('100%')
        .margin({ bottom: 6 })
      if (multiline) {
        TextArea({ text: value, placeholder: placeholder })
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textHint)
          .backgroundColor(Theme.surface)
          .borderRadius(8)
          .width('100%')
          .height(120)
          .onChange(onChange)
      } else {
        TextInput({ text: value, placeholder: placeholder })
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textHint)
          .backgroundColor(Theme.surface)
          .borderRadius(8)
          .width('100%')
          .height(46)
          .onChange(onChange)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 16 })
  }

  // 页面整体布局：顶部返回栏 + 可滚动的创建表单与保存按钮
  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick(() => router.back())
        Text('创建项目')
          .fontSize(20)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          this.Field('标题', this.title, (v: string) => this.title = v, '短剧标题', false)
          this.Field('故事提示词', this.prompt, (v: string) => this.prompt = v, '简述剧情或原始内容', true)
          this.Field('风格', this.style, (v: string) => this.style = v, '现代短剧', false)
          this.Field('目标受众', this.audience, (v: string) => this.audience = v, '大众受众', false)
          this.Field('画幅比例', this.aspectRatioStr, (v: string) => this.aspectRatioStr = v, '9:16', false)
          this.Field('分镜数量', this.shotCount, (v: string) => this.shotCount = v, '8', false)
          this.Field('单镜时长(秒)', this.duration, (v: string) => this.duration = v, '5', false)

          Button(this.saving ? '保存中…' : '保存')
            .width('100%')
            .height(50)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(Theme.primary)
            .borderRadius(12)
            .enabled(!this.saving)
            .onClick(() => this.save())
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
