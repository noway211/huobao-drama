import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { UseCases } from '../usecase/UseCases';
import { SettingsStore } from '../data/SettingsStore';
import { Character, AssetStatus } from '../model/DramaModels';
import { Theme } from '../common/Theme';

const DOMAIN = 0x0001;
const TAG = 'CharacterListPage';

interface CharListParams {
  projectId: number;
}

@Entry
@Component
struct CharacterListPage {
  @State title: string = '';
  @State characters: Character[] = [];
  @State loading: boolean = true;
  @State generatingCharId: number = 0;
  @State editingChar: Character | null = null;
  @State editText: string = '';
  @State previewImageUrl: string = '';
  // 数据刷新计数器：每次 characters 变更后 +1,塞进 ForEach key
  // 强制 ListItem 重建(否则 ArkUI 见 ch.id 相同会复用旧节点,导致
  // Text(ch.appearance) 等不重算,显示陈旧数据)
  @State refreshTick: number = 0;
  private projectId: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as CharListParams;
    if (params && params.projectId) {
      this.projectId = params.projectId;
    }
  }

  async onPageShow(): Promise<void> {
    this.loading = true;
    const project = await UseCases.getProject(this.projectId);
    this.title = project?.title ?? '角色列表';
    await this.reloadCharacters();
    this.loading = false;
  }

  private async reloadCharacters(): Promise<void> {
    this.characters = await UseCases.getCharacters(this.projectId);
    this.refreshTick++;
    hilog.info(DOMAIN, TAG, 'reloadCharacters: project=%{public}d count=%{public}d',
      this.projectId, this.characters.length);
    for (const ch of this.characters) {
      let localOk = false;
      let localSize = -1;
      if (ch.imageLocalPath && ch.imageLocalPath.length > 0) {
        try {
          const stat = fileIo.statSync(ch.imageLocalPath);
          localSize = stat.size;
          localOk = stat.size > 0;
        } catch (e) {
          localOk = false;
        }
      }
      const urlHead = ch.imageUrl ? ch.imageUrl.substring(0, 80) : '(null)';
      hilog.info(DOMAIN, TAG,
        'char id=%{public}d name=%{public}s status=%{public}d local=%{public}s size=%{public}d localOk=%{public}s urlHead=%{public}s',
        ch.id, ch.name, ch.imageStatus, ch.imageLocalPath ?? '(null)', localSize, localOk, urlHead);
    }
  }

  // 打开编辑弹层
  private startEdit(ch: Character): void {
    this.editText = ch.appearance;
    this.editingChar = ch;
  }

  // 保存编辑后的提示词
  private async saveEdit(): Promise<void> {
    const ch = this.editingChar;
    if (!ch || this.editText.trim().length === 0) {
      this.editingChar = null;
      return;
    }

    if (this.editText.trim() === ch.appearance) {
      this.editingChar = null;
      return;
    }

    const newText = this.editText.trim();
    this.editingChar = null;

    try {
      await UseCases.updateCharacterAppearance(ch.id, newText);
      promptAction.showToast({ message: `${ch.name} 提示词已更新` });
    } catch (e) {
      promptAction.showToast({ message: '提示词保存失败，请重试' });
    }
    await this.reloadCharacters();
  }

  // 取消编辑
  private cancelEdit(): void {
    this.editingChar = null;
  }

  // 为单个角色生成图片
  private async onGenerateImage(ch: Character): Promise<void> {
    const hasKey = await SettingsStore.hasApiKey();
    if (!hasKey) {
      promptAction.showToast({ message: '请先在设置中填写 API Key' });
      return;
    }

    this.generatingCharId = ch.id;
    const settings = await SettingsStore.load();
    const result = await UseCases.generateSingleCharacterImage(this.projectId, ch.id, settings);
    this.generatingCharId = 0;
    promptAction.showToast({ message: result.ok ? `${ch.name} 图片已生成` : `失败：${result.error}` });
    await this.reloadCharacters();
  }

  // 删除角色图片（软删除：DB status → PENDING + 清字段 + 删本地文件）
  private async onDeleteCharacterImageClick(ch: Character): Promise<void> {
    promptAction.showDialog({
      title: '删除角色图片？',
      message: '删除后需要重新生成。可在角色列表重新生成图片。',
      buttons: [
        { text: '取消', color: Theme.textSecondary },
        { text: '删除图片', color: Theme.primary }
      ]
    }).then(async (r) => {
      if (r.index !== 1) {
        return;
      }
      try {
        await UseCases.updateCharacterImage(
          ch.id, AssetStatus.PENDING, null, null, null
        );
      } catch (e) {
        promptAction.showToast({ message: '删除失败：' + ((e as Error).message ?? String(e)) });
        return;
      }
      // 容错删本地文件
      if (ch.imageLocalPath && ch.imageLocalPath.length > 0) {
        try {
          fileIo.unlinkSync(ch.imageLocalPath);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'unlink character image failed: %{public}s', (e as Error).message);
        }
      }
      promptAction.showToast({ message: '已删除' });
      await this.reloadCharacters();
    });
  }

  // 角色图片源：优先本地文件(必须带 file:// 前缀,Image 组件才能识别)
  private imgSrc(ch: Character): string {
    if (ch.imageLocalPath && ch.imageLocalPath.length > 0) {
      return ch.imageLocalPath.startsWith('file://') ? ch.imageLocalPath : `file://${ch.imageLocalPath}`;
    }
    if (ch.imageUrl && ch.imageUrl.length > 0) {
      return ch.imageUrl;
    }
    return '';
  }

  build() {
    Column() {
      // ── 顶部栏 ──
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
        Text(`共 ${this.characters.length} 个角色`)
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
      } else if (this.characters.length === 0) {
        Column() {
          Text('暂无角色')
            .fontSize(16)
            .fontColor(Theme.textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        List({ space: 12 }) {
          ForEach(this.characters, (ch: Character, index: number) => {
            ListItem() {
              Column() {
                // ── 角色头像 + 基本信息行 ──
                Row() {
                  if (this.imgSrc(ch).length > 0) {
                    Image(this.imgSrc(ch))
                      .width(64)
                      .height(64)
                      .borderRadius(8)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(Theme.surface)
                      .onClick(() => { this.previewImageUrl = this.imgSrc(ch); })
                  } else {
                    Column()
                      .width(64)
                      .height(64)
                      .borderRadius(8)
                      .backgroundColor(Theme.surfaceAlt)
                      .justifyContent(FlexAlign.Center)
                  }

                  Column() {
                    Text(ch.name)
                      .fontSize(16)
                      .fontColor(Theme.textPrimary)
                      .fontWeight(FontWeight.Bold)
                      .margin({ bottom: 4 })
                    Text(ch.role)
                      .fontSize(13)
                      .fontColor(Theme.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 12 })
                  .layoutWeight(1)

                  // 图片状态标识
                  if (ch.imageStatus === AssetStatus.PROCESSING) {
                    Text('生成中…')
                      .fontSize(11)
                      .fontColor(Theme.textHint)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor(Theme.surfaceAlt)
                      .borderRadius(4)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .margin({ bottom: 10 })

                // ── 外貌提示词 ──
                Text('外貌描述')
                  .fontSize(13)
                  .fontColor(Theme.textSecondary)
                  .margin({ bottom: 4 })
                Text(ch.appearance)
                  .fontSize(14)
                  .fontColor(Theme.textPrimary)
                  .lineHeight(20)
                  .width('100%')
                  .margin({ bottom: 4 })

                // ── 操作按钮行 ──
                Row() {
                  Button('编辑提示词')
                    .layoutWeight(1)
                    .height(40)
                    .fontSize(13)
                    .fontColor(Theme.textPrimary)
                    .backgroundColor(Theme.surfaceAlt)
                    .borderRadius(10)
                    .onClick(() => this.startEdit(ch))
                  Button(this.generatingCharId === ch.id ? '生成中…' : '生成图片')
                    .layoutWeight(1)
                    .height(40)
                    .fontSize(13)
                    .fontColor(Color.White)
                    .backgroundColor(this.generatingCharId !== 0 ? Theme.primaryDisabled : Theme.primary)
                    .borderRadius(10)
                    .margin({ left: 10 })
                    .enabled(this.generatingCharId === 0)
                    .onClick(() => this.onGenerateImage(ch))
                }
                .width('100%')

                // ── 删除按钮行（仅当有图片时显示） ──
                if (ch.imageStatus === AssetStatus.COMPLETED) {
                  Row() {
                    Blank().layoutWeight(1)
                    Button('删除图片')
                      .fontSize(13)
                      .backgroundColor(Theme.surfaceAlt)
                      .fontColor(Theme.textPrimary)
                      .height(32)
                      .padding({ left: 12, right: 12 })
                      .onClick((): void => { this.onDeleteCharacterImageClick(ch) })
                  }
                  .width('100%')
                  .margin({ top: 8 })
                }
              }
              .padding(16)
              .width('100%')
              .backgroundColor(Theme.surface)
              .borderRadius(10)
            }
          }, (ch: Character, index: number) => `${ch.id}_${this.refreshTick}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
        .scrollBar(BarState.Off)
      }

      // ── 编辑提示词弹层 ──
      if (this.editingChar) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .position({ x: 0, y: 0 })
          .onClick(() => this.cancelEdit())

        Column() {
          Column() {
            Text(`编辑 ${this.editingChar.name} 提示词`)
              .fontSize(18)
              .fontColor(Theme.textPrimary)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .margin({ bottom: 16 })

            TextArea({ text: this.editText, placeholder: '输入外貌描述，用于生成角色图片…' })
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
                .onClick(() => this.cancelEdit())
              Button('保存')
                .layoutWeight(1)
                .height(44)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(Theme.primary)
                .borderRadius(10)
                .margin({ left: 12 })
                .onClick(() => this.saveEdit())
            }
            .width('100%')
            .margin({ top: 16 })
          }
          .padding(24)
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

      // ── 角色图全屏预览 ──
      if (this.previewImageUrl.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .position({ x: 0, y: 0 })
          .onClick(() => { this.previewImageUrl = ''; })

        Column() {
          Image(this.previewImageUrl)
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
            .onClick(() => { this.previewImageUrl = ''; })

          Row() {
            Button('关闭')
              .width(100)
              .height(40)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor('#80000000')
              .borderRadius(20)
              .onClick(() => { this.previewImageUrl = ''; })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 16, bottom: 32 })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
