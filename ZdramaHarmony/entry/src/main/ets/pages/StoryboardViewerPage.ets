import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, Character } from '../model/DramaModels';
import { Theme } from '../common/Theme';

interface ViewerParams {
  projectId: number;
}

// 编辑提示词的弹层内边距
const DIALOG_PADDING = 24;

/** 弹层编辑的字段类型：图片提示词 / 视频提示词 */
type PromptField = 'image' | 'video';

/** 角色绑定展示数据（预计算后存入 @State，避免在 @Builder 中做数据处理） */
interface BindingDisplay {
  noBinding: boolean;
  allInvalid: boolean;
  displayChars: Character[];
  overflow: number;
}

@Entry
@Component
struct StoryboardViewerPage {
  @State title: string = '';
  @State shots: StoryboardShot[] = [];
  @State loading: boolean = true;
  @State shotCountText: string = '';
  @State editingShot: StoryboardShot | null = null;
  @State editText: string = '';
  @State editingField: PromptField = 'image';
  @State allCharacters: Character[] = [];
  @State editingShotForBinding: StoryboardShot | null = null;
  @State bindingSelectedIds: Set<number> = new Set();
  @State bindingDisplayMap: Record<number, BindingDisplay> = {};
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
    this.allCharacters = await UseCases.getCharacters(this.projectId);
    this.rebuildBindingDisplayMap();
    this.loading = false;
  }

  // 打开编辑弹层
  private startEditing(shot: StoryboardShot, field: PromptField): void {
    this.editText = field === 'image' ? shot.imagePrompt : shot.videoPrompt;
    this.editingField = field;
    this.editingShot = shot;
  }

  /** 保存编辑后的提示词，关闭弹层并刷新数据 */
  private async saveEdit(): Promise<void> {
    const shot = this.editingShot;
    if (!shot || this.editText.trim().length === 0) {
      this.editingShot = null;
      return;
    }

    const currentText = this.editingField === 'image' ? shot.imagePrompt : shot.videoPrompt;
    if (this.editText === currentText) {
      // 未修改直接关闭
      this.editingShot = null;
      return;
    }

    const shotId = shot.id;
    const newText = this.editText.trim();
    const fieldLabel = this.editingField === 'image' ? '图片' : '视频';
    this.editingShot = null;

    try {
      if (this.editingField === 'image') {
        await UseCases.updateShotPrompt(shotId, newText);
      } else {
        await UseCases.updateShotVideoPrompt(shotId, newText);
      }
      promptAction.showToast({ message: `#${shot.shotNumber} ${fieldLabel}提示词已更新` });
    } catch (e) {
      promptAction.showToast({ message: `${fieldLabel}提示词保存失败，请重试` });
    }
    // 刷新分镜数据
    this.shots = await UseCases.getStoryboards(this.projectId);
  }

  // 取消编辑
  private cancelEdit(): void {
    this.editingShot = null;
  }

  // 解析 shot.characterIds 字段为 number[] 预选集（双格式兼容）
  // 输入：null | '[]' | '[1,3,5]' | '["Alice","Bob"]'
  // 输出：Set<number>（已 remap 的 ID；无法匹配的 name 跳过）
  private resolvePreselectedIds(shot: StoryboardShot): Set<number> {
    const result = new Set<number>();
    if (!shot.characterIds || shot.characterIds.trim().length === 0) {
      return result;
    }
    let arr: Object;
    try {
      arr = JSON.parse(shot.characterIds);
    } catch (_e) {
      return result;
    }
    if (!Array.isArray(arr)) {
      return result;
    }
    // 优先按 number 处理
    let hasNumber = false;
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'number') {
        hasNumber = true;
        result.add(arr[i] as number);
      }
    }
    if (hasNumber) {
      // number 分支:复用 parseBindingIds 的过滤结果(保证 F2 修复后,预选与显示一致)
      const filtered = StoryboardViewerPage.parseBindingIds(shot, this.allCharacters);
      return new Set<number>(filtered);
    }
    // fallback：按 name 匹配
    const nameToId = new Map<string, number>();
    for (const ch of this.allCharacters) {
      nameToId.set(ch.name, ch.id);
    }
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'string') {
        const id = nameToId.get(arr[i] as string);
        if (id !== undefined) {
          result.add(id);
        }
      }
    }
    return result;
  }

  // 打开角色绑定编辑弹层
  private openBindingEditor(shot: StoryboardShot): void {
    this.editingShotForBinding = shot;
    this.bindingSelectedIds = this.resolvePreselectedIds(shot);
  }

  // 切换角色的选中状态
  private toggleBindingSelection(characterId: number): void {
    if (this.bindingSelectedIds.has(characterId)) {
      this.bindingSelectedIds.delete(characterId);
    } else {
      this.bindingSelectedIds.add(characterId);
    }
    // 触发 UI 重渲（@State Set 引用未变，需替换为新 Set）
    this.bindingSelectedIds = new Set(this.bindingSelectedIds);
  }

  // 保存绑定并关闭弹层
  private async saveBinding(): Promise<void> {
    const shot = this.editingShotForBinding;
    if (!shot) {
      return;
    }
    const ids: number[] = [];
    for (const id of this.bindingSelectedIds) {
      ids.push(id);
    }
    ids.sort((a, b) => a - b);
    this.editingShotForBinding = null;
    this.bindingSelectedIds = new Set();
    try {
      await UseCases.updateShotCharacterIds(shot.id, ids);
      promptAction.showToast({ message: `#${shot.shotNumber} 角色绑定已更新` });
    } catch (e) {
      promptAction.showToast({ message: '角色绑定保存失败，请重试' });
    }
    this.shots = await UseCases.getStoryboards(this.projectId);
    this.rebuildBindingDisplayMap();
  }

  // 取消绑定编辑
  private cancelBindingEdit(): void {
    this.editingShotForBinding = null;
    this.bindingSelectedIds = new Set();
  }

  // 把 Shot.characterIds 解析成"当前项目里实际存在且可显示"的 number[]。
  // 单一真相源:computeBindingDisplay、bindingSummary、resolvePreselectedIds 都走它。
  // 输入: null | '' | '[]' | '[1,3,5]' | '["Alice","Bob"]' | 单值 | 无效 JSON
  // 输出: 已过滤(number 且 ID 存在于 allCharacters)的 number[],空集对应"无绑定"
  private static parseBindingIds(shot: StoryboardShot, allCharacters: Character[]): number[] {
    if (!shot.characterIds || shot.characterIds.trim().length === 0) {
      return [];
    }
    const validIds = new Set<number>(allCharacters.map(c => c.id));
    const result = new Set<number>();
    try {
      const arr = JSON.parse(shot.characterIds) as Object;
      if (Array.isArray(arr)) {
        for (let i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'number' && validIds.has(arr[i] as number)) {
            result.add(arr[i] as number);
          }
        }
      }
    } catch (_e) { /* ignore malformed JSON */ }
    // 用 sorted 数组保持稳定顺序(便于 bindingSummary 长度与渲染一致)
    return Array.from(result).sort((a, b) => a - b);
  }

  // 计算单个角色头像的 file:// 源（空字符串表示用首字母占位）
  private avatarSrc(ch: Character): string {
    if (ch.imageLocalPath && ch.imageLocalPath.length > 0) {
      return ch.imageLocalPath.startsWith('file://') ? ch.imageLocalPath : `file://${ch.imageLocalPath}`;
    }
    return '';
  }

  // 计算单个分镜的角色绑定展示数据（供 @Builder 渲染使用，避免在 UI 体内做数据处理）
  private computeBindingDisplay(shot: StoryboardShot, allCharacters: Character[]): BindingDisplay {
    if (shot.characterIds === null || shot.characterIds.trim().length === 0) {
      return { noBinding: true, allInvalid: false, displayChars: [], overflow: 0 };
    }
    const validIds = StoryboardViewerPage.parseBindingIds(shot, allCharacters);
    const idToChar = new Map<number, Character>();
    for (const ch of allCharacters) {
      idToChar.set(ch.id, ch);
    }
    const displayChars: Character[] = [];
    const shownIds = validIds.slice(0, 3);
    for (const id of shownIds) {
      const ch = idToChar.get(id);
      if (ch) {
        displayChars.push(ch);
      }
    }
    const overflow = Math.max(0, validIds.length - 3);

    return {
      noBinding: false,
      allInvalid: validIds.length === 0,
      displayChars: displayChars,
      overflow: overflow
    };
  }

  // 重建全部分镜的展示数据缓存（在 shots/allCharacters 变更后调用）
  private rebuildBindingDisplayMap(): void {
    const map: Record<number, BindingDisplay> = {};
    for (const shot of this.shots) {
      map[shot.id] = this.computeBindingDisplay(shot, this.allCharacters);
    }
    this.bindingDisplayMap = map;
  }

  // 顶部"角色"行的副标题："0 个" / "3 个" 等
  private bindingSummary(shot: StoryboardShot): string {
    const count = StoryboardViewerPage.parseBindingIds(shot, this.allCharacters).length;
    return `${count} 个`;
  }

  // 角色头像行：展示已绑角色的圆形头像（无图用首字母占位）+ 溢出数字徽标
  @Builder
  BindingAvatarsRow(display: BindingDisplay) {
    Row() {
      if (display.noBinding) {
        Text('未绑定角色')
          .fontSize(13)
          .fontColor(Theme.textHint)
      } else if (display.allInvalid) {
        Text('绑定已失效，请重新编辑')
          .fontSize(13)
          .fontColor(Theme.textHint)
      } else {
        ForEach(display.displayChars, (ch: Character) => {
          this.BindingAvatar(this.avatarSrc(ch), ch)
        }, (ch: Character) => ch.id.toString())
        if (display.overflow > 0) {
          Text(`+${display.overflow}`)
            .fontSize(12)
            .fontColor(Theme.textSecondary)
            .height(36)
            .padding({ left: 8, right: 8 })
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(18)
            .margin({ left: 4 })
        }
      }
    }
    .width('100%')
  }

  // 单个角色头像（36x36 圆形）：有图显示图片，无图显示首字母占位
  @Builder
  BindingAvatar(src: string, ch: Character) {
    if (src.length > 0) {
      Image(src)
        .width(36)
        .height(36)
        .borderRadius(18)
        .objectFit(ImageFit.Cover)
        .backgroundColor(Theme.surfaceAlt)
        .margin({ right: 6 })
    } else {
      Column() {
        Text(ch.name.length > 0 ? ch.name.substring(0, 1) : '?')
          .fontSize(14)
          .fontColor(Theme.textPrimary)
          .fontWeight(FontWeight.Bold)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(Theme.surfaceAlt)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: 6 })
    }
  }

  // 弹层里 2xN 网格中的单个角色可选卡片
  @Builder
  CharacterPickCell(ch: Character, selected: boolean, src: string) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (src.length > 0) {
          Image(src)
            .width('100%')
            .height(80)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
            .backgroundColor(Theme.surfaceAlt)
        } else {
          Column() {
            Text(ch.name.length > 0 ? ch.name.substring(0, 1) : '?')
              .fontSize(28)
              .fontColor(Theme.textPrimary)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .height(80)
          .borderRadius(8)
          .backgroundColor(Theme.surfaceAlt)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        if (selected) {
          Text('✓')
            .fontSize(14)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor(Theme.primary)
            .textAlign(TextAlign.Center)
            .margin(4)
        }
      }
      .width('100%')
      .height(80)

      Text(ch.name)
        .fontSize(13)
        .fontColor(Theme.textPrimary)
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 6 })

      Text(ch.role)
        .fontSize(11)
        .fontColor(Theme.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .padding(8)
    .width('100%')
    .backgroundColor(selected ? '#33000000' : '#1A000000')
    .borderRadius(10)
    .borderWidth(selected ? 1 : 0)
    .borderColor(selected ? Theme.primary : Color.Transparent)
    .onClick(() => this.toggleBindingSelection(ch.id))
  }

  // 格式化其余分镜信息（不含图片/视频提示词，已独立展示）
  private formatMeta(shot: StoryboardShot): string {
    let text = `动作：${shot.action}\n`;
    text += `对白：${shot.dialogue}\n`;
    text += `镜头：${shot.camera}\n`;
    text += `时长：${shot.durationSeconds} 秒`;
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
                // ── 分镜标题 ──
                Text(`#${shot.shotNumber}  ${shot.scene}`)
                  .fontSize(16)
                  .fontColor(Theme.textPrimary)
                  .fontWeight(FontWeight.Bold)
                  .width('100%')
                  .margin({ bottom: 10 })

                // ── 图片提示词（可点击编辑） ──
                PromptCardBuilder('图片提示词', shot.imagePrompt, () => {
                  this.startEditing(shot, 'image');
                })

                // ── 视频提示词（可点击编辑） ──
                PromptCardBuilder('视频提示词', shot.videoPrompt, () => {
                  this.startEditing(shot, 'video');
                })

                // ── 角色绑定卡片 ──
                Column() {
                  Row() {
                    Text('角色')
                      .fontSize(13)
                      .fontColor(Theme.textSecondary)
                      .layoutWeight(1)
                    Text(this.bindingSummary(shot))
                      .fontSize(12)
                      .fontColor(Theme.textHint)
                      .margin({ right: 8 })
                    Text('编辑')
                      .fontSize(12)
                      .fontColor(Theme.primary)
                      .onClick(() => this.openBindingEditor(shot))
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .margin({ bottom: 8 })

                  this.BindingAvatarsRow(this.bindingDisplayMap[shot.id] ?? { noBinding: true, allInvalid: false, displayChars: [], overflow: 0 })
                }
                .padding(12)
                .width('100%')
                .backgroundColor('#1A000000')
                .borderRadius(8)
                .margin({ bottom: 10 })

                // ── 其余信息 ──
                Text(this.formatMeta(shot))
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

      // ── 编辑提示词弹层 ──
      if (this.editingShot) {
        // 遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .position({ x: 0, y: 0 })
          .onClick(() => this.cancelEdit())

        // 对话框
        Column() {
          Column() {
            Text(`编辑 #${this.editingShot.shotNumber} ${this.editingField === 'image' ? '图片' : '视频'}提示词`)
              .fontSize(18)
              .fontColor(Theme.textPrimary)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .margin({ bottom: 16 })

            TextArea({ text: this.editText, placeholder: '输入新的提示词…' })
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

      // ── 角色绑定编辑弹层 ──
      if (this.editingShotForBinding) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .position({ x: 0, y: 0 })
          .onClick(() => this.cancelBindingEdit())

        Column() {
          Column() {
            Text(`编辑 #${this.editingShotForBinding.shotNumber} 角色绑定`)
              .fontSize(18)
              .fontColor(Theme.textPrimary)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .margin({ bottom: 8 })

            Text(`已选 ${this.bindingSelectedIds.size} 个`)
              .fontSize(13)
              .fontColor(Theme.textSecondary)
              .width('100%')
              .margin({ bottom: 16 })

            if (this.allCharacters.length === 0) {
              Text('暂无可绑定角色，请先提取角色')
                .fontSize(14)
                .fontColor(Theme.textHint)
                .width('100%')
                .padding(20)
                .textAlign(TextAlign.Center)
            } else {
              Grid() {
                ForEach(this.allCharacters, (ch: Character) => {
                  GridItem() {
                    this.CharacterPickCell(ch, this.bindingSelectedIds.has(ch.id), this.avatarSrc(ch))
                  }
                }, (ch: Character) => ch.id > 0 ? ch.id.toString() : ch.name)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(10)
              .width('100%')
              .height(280)
            }

            Row() {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .fontSize(14)
                .fontColor(Theme.textSecondary)
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(10)
                .onClick(() => this.cancelBindingEdit())
              Button('保存')
                .layoutWeight(1)
                .height(44)
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(Theme.primary)
                .borderRadius(10)
                .margin({ left: 12 })
                .onClick(() => this.saveBinding())
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}

/**
 * 提示词卡片 Builder — 展示标签 + 文本内容 + "点击编辑" 链接。
 * 复用图片/视频两种提示词的展示样式。
 */
@Builder
function PromptCardBuilder(label: string, text: string, onClick: () => void) {
  Column() {
    Text(label)
      .fontSize(13)
      .fontColor(Theme.textSecondary)
      .margin({ bottom: 4 })
    Text(text)
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
    .onClick(() => onClick())
  }
  .padding(12)
  .width('100%')
  .backgroundColor('#1A000000')
  .borderRadius(8)
  .margin({ bottom: 10 })
}