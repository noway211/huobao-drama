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

  async onPageShow(): Promise<void> {
    const s = await SettingsStore.load();
    this.apiKey = s.apiKey;
    this.baseUrl = s.baseUrl;
    this.textModel = s.textModel;
    this.imageModel = s.imageModel;
    this.videoModel = s.videoModel;
  }

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

  async save(): Promise<void> {
    await SettingsStore.save(this.currentSettings());
    promptAction.showToast({ message: '已保存' });
  }

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
    await SettingsStore.save(this.currentSettings());
    const repo = new AgnesTextRepository();
    // Reuse rewriteScript with a tiny payload as a lightweight ping.
    const result = await repo.rewriteScript(this.currentSettings(), 'ping');
    this.testing = false;
    promptAction.showToast({ message: result.ok ? '连接成功' : `连接失败：${result.error}` });
  }

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
          this.Field('文本模型', this.textModel, (v: string) => this.textModel = v, '例如 gpt-4o')
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
