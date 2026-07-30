import { router, promptAction } from '@kit.ArkUI';
import { SettingsStore } from '../data/SettingsStore';
import { AgnesSettings, defaultSettings } from '../model/AgnesSettings';
import { AgnesTextRepository } from '../remote/AgnesTextRepository';
import { Theme } from '../common/Theme';

@Entry
@Component
struct SettingsPage {
  @State apiKey: string = '';
  @State baseUrl: string = '';
  @State textModel: string = '';
  @State imageModel: string = '';
  @State videoModel: string = '';
  @State testing: boolean = false;

  // 页面显示时从本地存储读取已保存的设置并回填到输入框
  async onPageShow(): Promise<void> {
    const s = await SettingsStore.load();
    this.apiKey = s.apiKey;
    this.baseUrl = s.baseUrl;
    this.textModel = s.textModel;
    this.imageModel = s.imageModel;
    this.videoModel = s.videoModel;
  }

  // 将当前输入框内容组装为设置对象（超时使用默认值）
  private currentSettings(): AgnesSettings {
    const d = defaultSettings();
    return {
      apiKey: this.apiKey,
      baseUrl: this.baseUrl,
      textModel: this.textModel,
      imageModel: this.imageModel,
      videoModel: this.videoModel,
      requestTimeoutSeconds: d.requestTimeoutSeconds
    };
  }

  // 保存当前设置到本地存储并提示结果
  async save(): Promise<void> {
    try {
      await SettingsStore.save(this.currentSettings());
      promptAction.showToast({ message: '设置已保存' });
    } catch (e) {
      promptAction.showToast({ message: '设置保存失败' });
    }
  }

  // 测试文本模型连通性：校验必填项，保存设置后发起测试并提示结果
  async testConnection(): Promise<void> {
    if (this.apiKey.trim().length === 0) {
      promptAction.showToast({ message: '请先填写 API Key' });
      return;
    }
    if (this.textModel.trim().length === 0) {
      promptAction.showToast({ message: '请先填写文本模型' });
      return;
    }
    this.testing = true;
    try {
      await SettingsStore.save(this.currentSettings());
    } catch (e) {
      // 非致命错误：仍使用内存中的设置继续测试
      // Non-fatal: still attempt the test with in-memory settings.
    }
    const repo = new AgnesTextRepository();
    const result = await repo.testTextModel(this.currentSettings());
    this.testing = false;
    promptAction.showToast({ message: result.ok ? '连接测试成功' : `连接测试失败：${result.error}` });
  }

  // 通用带标签的单行输入项：标签 + 文本输入框
  @Builder
  Field(label: string, value: string, onChange: (v: string) => void, placeholder: string) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor(Theme.textSecondary)
        .width('100%')
        .margin({ bottom: 6 })
      TextInput({ text: value, placeholder: placeholder })
        .fontColor(Theme.textPrimary)
        .placeholderColor(Theme.textHint)
        .backgroundColor(Theme.surface)
        .borderRadius(8)
        .width('100%')
        .height(46)
        .onChange(onChange)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 16 })
  }

  // 页面整体布局：顶部返回栏 + 可滚动的各项设置表单与测试/保存按钮
  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick(() => router.back())
        Text('设置')
          .fontSize(20)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          this.Field('API Key', this.apiKey, (v: string) => this.apiKey = v, 'sk-...')
          this.Field('Base URL', this.baseUrl, (v: string) => this.baseUrl = v, 'https://apihub.agnes-ai.com/')
          this.Field('文本模型', this.textModel, (v: string) => this.textModel = v, 'agnes-2.0-flash')
          this.Field('图片模型', this.imageModel, (v: string) => this.imageModel = v, 'agnes-image-2.0-flash')
          this.Field('视频模型', this.videoModel, (v: string) => this.videoModel = v, 'agnes-video-v2.0')

          Button(this.testing ? '测试中…' : '测试文本模型')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontColor(Theme.textPrimary)
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(10)
            .enabled(!this.testing)
            .margin({ bottom: 12 })
            .onClick(() => this.testConnection())

          Button('保存')
            .width('100%')
            .height(50)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(Theme.primary)
            .borderRadius(12)
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
