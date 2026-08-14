import { router, promptAction } from '@kit.ArkUI';
import { SettingsStore } from '../data/SettingsStore';
import { AgnesSettings, defaultSettings } from '../model/AgnesSettings';
import {
  SCRIPT_CREATE_PROMPT,
  SCRIPT_REWRITE_PROMPT,
  CHARACTER_EXTRACT_PROMPT,
  STORYBOARD_PROMPT
} from '../model/PromptDefaults';
import { AgnesTextRepository } from '../remote/AgnesTextRepository';
import { Theme } from '../common/Theme';

// 提示词保存/重置的 patch 参数类型（ArkTS 严格模式不允许 inline object literal 当类型）
interface PromptSavePatch {
  customScriptCreatePrompt?: string;
  customScriptRewritePrompt?: string;
  customCharacterExtractPrompt?: string;
  customStoryboardPrompt?: string;
}
interface PromptResetPatch {
  customScriptCreatePrompt?: true;
  customScriptRewritePrompt?: true;
  customCharacterExtractPrompt?: true;
  customStoryboardPrompt?: true;
}

@Entry
@Component
struct SettingsPage {
  @State apiKey: string = '';
  @State baseUrl: string = '';
  @State textModel: string = '';
  @State imageModel: string = '';
  @State videoModel: string = '';
  @State testing: boolean = false;
  // 提示词管理 Modal 状态
  @State showPromptModal: boolean = false;
  @State activePromptTab: number = 0;
  @State editScriptCreatePrompt: string = '';
  @State editScriptRewritePrompt: string = '';
  @State editCharacterExtractPrompt: string = '';
  @State editStoryboardPrompt: string = '';

  // 页面显示时从本地存储读取已保存的设置并回填到输入框
  async onPageShow(): Promise<void> {
    const s = await SettingsStore.load();
    this.apiKey = s.apiKey;
    this.baseUrl = s.baseUrl;
    this.textModel = s.textModel;
    this.imageModel = s.imageModel;
    this.videoModel = s.videoModel;
    // 4 个自定义 prompt 同步：未编辑过显示默认，便于用户看到原始内容
    this.editScriptCreatePrompt = s.customScriptCreatePrompt ?? SCRIPT_CREATE_PROMPT;
    this.editScriptRewritePrompt = s.customScriptRewritePrompt ?? SCRIPT_REWRITE_PROMPT;
    this.editCharacterExtractPrompt = s.customCharacterExtractPrompt ?? CHARACTER_EXTRACT_PROMPT;
    this.editStoryboardPrompt = s.customStoryboardPrompt ?? STORYBOARD_PROMPT;
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

  // ────────────── 提示词管理 ──────────────

  // 打开 Modal：从 store 重新拉最新值，避免外部修改不同步
  private async openPromptModal(): Promise<void> {
    await this.refreshPromptStatesFromStore();
    this.showPromptModal = true;
  }

  // 关闭 Modal
  private closePromptModal(): void {
    this.showPromptModal = false;
  }

  // 从 store 拉最新 custom*；无值则用默认常量
  private async refreshPromptStatesFromStore(): Promise<void> {
    const s = await SettingsStore.load();
    this.editScriptCreatePrompt = s.customScriptCreatePrompt ?? SCRIPT_CREATE_PROMPT;
    this.editScriptRewritePrompt = s.customScriptRewritePrompt ?? SCRIPT_REWRITE_PROMPT;
    this.editCharacterExtractPrompt = s.customCharacterExtractPrompt ?? CHARACTER_EXTRACT_PROMPT;
    this.editStoryboardPrompt = s.customStoryboardPrompt ?? STORYBOARD_PROMPT;
  }

  // 保存一批 prompt（trim 后空串 → undefined → 触发 store.delete，下次调用走默认）
  // 用 patch 对象而非动态 key 索引：规避 ArkTS strict typing 的 arkts-no-props-by-index
  private async savePrompts(
    patch: PromptSavePatch,
    label: string
  ): Promise<void> {
    const s = await SettingsStore.load();
    if (patch.customScriptCreatePrompt !== undefined) {
      const v = patch.customScriptCreatePrompt.trim();
      s.customScriptCreatePrompt = v.length > 0 ? v : undefined;
    }
    if (patch.customScriptRewritePrompt !== undefined) {
      const v = patch.customScriptRewritePrompt.trim();
      s.customScriptRewritePrompt = v.length > 0 ? v : undefined;
    }
    if (patch.customCharacterExtractPrompt !== undefined) {
      const v = patch.customCharacterExtractPrompt.trim();
      s.customCharacterExtractPrompt = v.length > 0 ? v : undefined;
    }
    if (patch.customStoryboardPrompt !== undefined) {
      const v = patch.customStoryboardPrompt.trim();
      s.customStoryboardPrompt = v.length > 0 ? v : undefined;
    }
    try {
      await SettingsStore.save(s);
      promptAction.showToast({ message: `${label} 已保存` });
    } catch (e) {
      promptAction.showToast({ message: `${label} 保存失败` });
    }
  }

  // 重置一批 prompt 到默认（清 store key + UI 编辑态切回默认常量）
  private async resetPrompts(
    patch: PromptResetPatch,
    label: string
  ): Promise<void> {
    const s = await SettingsStore.load();
    if (patch.customScriptCreatePrompt === true) s.customScriptCreatePrompt = undefined;
    if (patch.customScriptRewritePrompt === true) s.customScriptRewritePrompt = undefined;
    if (patch.customCharacterExtractPrompt === true) s.customCharacterExtractPrompt = undefined;
    if (patch.customStoryboardPrompt === true) s.customStoryboardPrompt = undefined;
    try {
      await SettingsStore.save(s);
      await this.refreshPromptStatesFromStore();
      promptAction.showToast({ message: `${label} 已重置为默认` });
    } catch (e) {
      promptAction.showToast({ message: `${label} 重置失败` });
    }
  }

  // 通用：标签 + 字数提示 + 多行 TextArea
  @Builder
  PromptField(label: string, value: string, onChange: (v: string) => void, hint: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
          .layoutWeight(1)
        Text(hint)
          .fontSize(11)
          .fontColor(Theme.textHint)
      }
      .width('100%')
      .margin({ bottom: 6 })
      TextArea({ text: value, placeholder: '在此输入自定义提示词…清空则使用默认值' })
        .fontSize(13)
        .fontColor(Theme.textPrimary)
        .placeholderColor(Theme.textHint)
        .backgroundColor(Theme.surface)
        .borderRadius(8)
        .width('100%')
        .height(400)
        .padding(12)
        .onChange(onChange)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 12 })
  }

  // 底部双按钮行：重置 + 保存
  @Builder
  PromptActions(resetHandler: () => void, saveHandler: () => void) {
    Row() {
      Button('重置为默认')
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .fontColor(Theme.textPrimary)
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(10)
        .onClick(resetHandler)
      Button('保存当前')
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(Theme.primary)
        .borderRadius(10)
        .margin({ left: 8 })
        .onClick(saveHandler)
    }
    .width('100%')
  }

  // Modal 内容：顶部关闭栏 + Tabs (脚本/角色提取/分镜)
  @Builder
  PromptModal() {
    Column() {
      // 顶部关闭栏
      Row() {
        Button('关闭')
          .fontSize(14)
          .backgroundColor(Theme.surfaceAlt)
          .fontColor(Theme.textPrimary)
          .height(36)
          .onClick(() => this.closePromptModal())
        Text('管理提示词')
          .fontSize(18)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('')
          .width(64)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Tabs({ index: $$this.activePromptTab, barPosition: BarPosition.Start }) {
        // Tab 1: 脚本（2 个 TextArea：创作 + 改写）
        TabContent() {
          Scroll() {
            Column() {
              this.PromptField(
                '创作剧本（用于"生成剧本"流程）',
                this.editScriptCreatePrompt,
                (v: string) => this.editScriptCreatePrompt = v,
                `默认 ${SCRIPT_CREATE_PROMPT.length} 字`
              )
              this.PromptField(
                '改写剧本（用于"改写剧本"流程）',
                this.editScriptRewritePrompt,
                (v: string) => this.editScriptRewritePrompt = v,
                `默认 ${SCRIPT_REWRITE_PROMPT.length} 字`
              )
              this.PromptActions(
                () => this.resetPrompts({ customScriptCreatePrompt: true, customScriptRewritePrompt: true }, '脚本'),
                () => this.savePrompts({ customScriptCreatePrompt: this.editScriptCreatePrompt, customScriptRewritePrompt: this.editScriptRewritePrompt }, '脚本')
              )
            }
            .width('100%')
            .padding(16)
          }
          .layoutWeight(1)
          .width('100%')
        }
        .tabBar('脚本')

        // Tab 2: 角色提取
        TabContent() {
          Scroll() {
            Column() {
              this.PromptField(
                '角色提取（从剧本抽取 name/role/description/appearance/personality）',
                this.editCharacterExtractPrompt,
                (v: string) => this.editCharacterExtractPrompt = v,
                `默认 ${CHARACTER_EXTRACT_PROMPT.length} 字`
              )
              this.PromptActions(
                () => this.resetPrompts({ customCharacterExtractPrompt: true }, '角色提取'),
                () => this.savePrompts({ customCharacterExtractPrompt: this.editCharacterExtractPrompt }, '角色提取')
              )
            }
            .width('100%')
            .padding(16)
          }
          .layoutWeight(1)
          .width('100%')
        }
        .tabBar('角色提取')

        // Tab 3: 分镜
        TabContent() {
          Scroll() {
            Column() {
              this.PromptField(
                '分镜（拆解剧本为分镜 JSON，文字字段中文，image/video prompt 英文）',
                this.editStoryboardPrompt,
                (v: string) => this.editStoryboardPrompt = v,
                `默认 ${STORYBOARD_PROMPT.length} 字`
              )
              this.PromptActions(
                () => this.resetPrompts({ customStoryboardPrompt: true }, '分镜'),
                () => this.savePrompts({ customStoryboardPrompt: this.editStoryboardPrompt }, '分镜')
              )
            }
            .width('100%')
            .padding(16)
          }
          .layoutWeight(1)
          .width('100%')
        }
        .tabBar('分镜')
      }
      .layoutWeight(1)
      .width('100%')
      .barMode(BarMode.Fixed)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
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

  // 页面整体布局：顶部返回栏 + 可滚动的各项设置表单与测试/提示词/保存按钮
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

          Button('管理提示词')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontColor(Theme.textPrimary)
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(10)
            .margin({ bottom: 12 })
            .onClick(() => this.openPromptModal())

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
    .bindContentCover($$this.showPromptModal, this.PromptModal)
  }
}
