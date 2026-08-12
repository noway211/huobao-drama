# 鸿蒙端分镜角色绑定 UI — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `StoryboardViewerPage` 为每个分镜卡片新增"角色"区(头像 + 数字徽标 + 编辑按钮),弹多选弹层支持查看/调整/保存角色绑定,改完后下次点"生成图片"时 `buildCharacterReferences` 自动用新绑定。

**Architecture:** UI 层解析 `characterIds` 双格式(number[] / string[])做预选,保存时统一写 number[] JSON;数据层新增 3 个薄方法直写 `character_ids` 列,不做语义转换;不调用 `remapCharacterNamesToIds`(老数据靠 UI 解析兼容)。

**Tech Stack:** HarmonyOS NEXT / ArkTS / `relationalStore` / ArkUI `@State` / 现有 `Theme` 配色。

## Global Constraints

- ETS / ArkTS 严格类型,所有 import 必须命名导入;`@State` 状态变量只能装饰 struct 字段
- 鸿蒙数据库 schema 不变 — 只 `UPDATE storyboards SET character_ids = ?, updated_at = ? WHERE id = ?`
- 新增方法风格必须与同文件现有方法完全一致(参照 `updateShotImagePrompt` / `updateShotImage` / `updateShotVideo`)
- 主题色只用 `Theme.surface` / `Theme.surfaceAlt` / `Theme.primary` / `Theme.primaryDisabled` / `Theme.textPrimary` / `Theme.textSecondary` / `Theme.textHint` / `Theme.border`,不要硬编码十六进制色(透明背景 `#1A000000` / 遮罩 `#66000000` 例外,这是现有 CharacterListPage 也用的模式)
- 弹层风格参照 `CharacterListPage.ets:271-330` 的"遮罩 + 居中卡片"模式
- 不调用 `UseCases.remapCharacterNamesToIds` — 老数据(name 字符串数组)由 UI 解析时兼容
- 不动 `ProjectDetailPage.ets` / `CharacterListPage.ets` / `module.json5` / `EntryAbility.ets` / Android 任何文件
- 不加"重新生成本分镜图片"入口,不改 `buildCharacterReferences` 内部
- struct 内的 UI 构造用普通方法(返回 void)而不是 `@Builder` 函数,避免 @Builder 闭包不能引用 `this` 的问题

---

### Task 1: 数据层 — `updateStoryboardCharacterIds` 三件套

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/data/StoryboardLocalDataSource.ets:130-145`(在 `updateShotImagePrompt` 之后插入)
- Modify: `ZdramaHarmony/entry/src/main/ets/data/DramaRepository.ets:85-93`(在 `updateShotImagePrompt` 之后插入)
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets`(在 `updateShotVideoPrompt` 之后新增公开静态方法)

**Interfaces:**
- Consumes: 现有 `StoryboardShot.characterIds: string | null` 字段、现有 `DramaDatabase.getStore()`、`UseCases.repo` 实例
- Produces:
  - `StoryboardLocalDataSource.updateStoryboardCharacterIds(shotId: number, characterIdsJson: string): Promise<void>`
  - `DramaRepository.updateStoryboardCharacterIds(shotId: number, characterIdsJson: string): Promise<void>`
  - `UseCases.updateShotCharacterIds(shotId: number, characterIds: number[]): Promise<void>`

- [ ] **Step 1: 在 `StoryboardLocalDataSource.ets` 插入新方法**

在 `updateShotImagePrompt` 方法(line 134-143)之后、文件末尾前,新增:

```ts
/**
 * 更新单个分镜的角色绑定（character_ids 列，存 number[] JSON 字符串）。
 * 参照 updateShotImagePrompt 的查询模式。
 */
async updateStoryboardCharacterIds(
  shotId: number,
  characterIdsJson: string
): Promise<void> {
  const store = await DramaDatabase.getStore();
  const values: relationalStore.ValuesBucket = {
    'character_ids': characterIdsJson,
    'updated_at': Date.now()
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', shotId);
  await store.update(values, predicates);
}
```

- [ ] **Step 2: 在 `DramaRepository.ets` 插入转发方法**

在 `updateShotImagePrompt` 方法(line 86-88)之后,新增:

```ts
// 更新单个分镜的角色绑定（存 number[] JSON 字符串）
async updateStoryboardCharacterIds(
  shotId: number,
  characterIdsJson: string
): Promise<void> {
  return this.storyboards.updateStoryboardCharacterIds(shotId, characterIdsJson);
}
```

- [ ] **Step 3: 在 `UseCases.ets` 插入公开静态方法**

定位 `updateShotVideoPrompt` 公开方法(通常紧邻 `updateShotImagePrompt` 之后,带 `static async`),在它之后,新增:

```ts
/**
 * 写回分镜的角色绑定(规范化为 number[] JSON 字符串)。
 * 空数组写空字符串(数据库列允许,parseCharacterIds 视作无绑定)。
 */
static async updateShotCharacterIds(
  shotId: number,
  characterIds: number[]
): Promise<void> {
  const json = characterIds.length > 0 ? JSON.stringify(characterIds) : '';
  await UseCases.repo.updateStoryboardCharacterIds(shotId, json);
}
```

- [ ] **Step 4: 编译验证**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
./hvigorw assembleHap
```

期望:`> hvigorw BUILD SUCCESSFUL`。Task 2 还没做,只验证数据层 3 个方法编译通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/data/StoryboardLocalDataSource.ets \
        ZdramaHarmony/entry/src/main/ets/data/DramaRepository.ets \
        ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets
git commit -m "feat(harmony): 分镜角色绑定写入 API"
```

提交信息体写明:
- 3 个新方法,职责单一(写库 / 转发 / 规范化 + 转发)
- 写库格式统一为 number[] JSON 字符串
- 不消费此 API 的代码尚未提交(Task 2)

---

### Task 2: UI — `StoryboardViewerPage` 角色卡片 + 多选弹层

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/pages/StoryboardViewerPage.ets`(整文件)

**Interfaces:**
- Consumes:
  - 现有 `StoryboardShot.characterIds: string | null`
  - Task 1 新增的 `UseCases.updateShotCharacterIds(shotId, ids: number[])`
  - 现有 `UseCases.getCharacters(projectId): Promise<Character[]>`
  - 现有 `Theme.*` 颜色
- Produces:
  - 角色区:展示已绑角色头像 + 数字徽标 + "编辑"链接
  - 多选弹层:全项目角色网格,预选当前绑定,保存时调 `UseCases.updateShotCharacterIds`

- [ ] **Step 1: 修改文件顶部 import**

修改 line 1-4,从:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot } from '../model/DramaModels';
import { Theme } from '../common/Theme';
```

改为:

```ts
import { router, promptAction } from '@kit.ArkUI';
import { UseCases } from '../usecase/UseCases';
import { StoryboardShot, Character } from '../model/DramaModels';
import { Theme } from '../common/Theme';
```

- [ ] **Step 2: 在 struct 字段区插入新状态**

修改 line 18-26(`@Component struct StoryboardViewerPage` 内),在 `@State editingField: PromptField = 'image';` 之后,新增 3 个 `@State`:

```ts
@State allCharacters: Character[] = [];
@State editingShotForBinding: StoryboardShot | null = null;
@State bindingSelectedIds: Set<number> = new Set();
```

`private projectId: number = 0;` 保留不变。

- [ ] **Step 3: 在 `onPageShow` 末尾加载角色数据**

修改 `onPageShow` 方法(line 37-50),在 `this.loading = false;` 之前新增:

```ts
this.allCharacters = await UseCases.getCharacters(this.projectId);
```

- [ ] **Step 4: 在 `cancelEdit()` 之后新增 5 个私有方法**

```ts
// 解析 shot.characterIds 字段为 number[] 预选集(双格式兼容)
// 输入: null | '[]' | '[1,3,5]' | '["Alice","Bob"]'
// 输出: Set<number>(已 remap 的 ID;无法匹配的 name 跳过)
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
    const validIds = new Set<number>(this.allCharacters.map(c => c.id));
    return new Set<number>([...result].filter(id => validIds.has(id)));
  }
  // fallback: 按 name 匹配
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
  // 触发 UI 重渲(@State Set 引用未变,需替换为新 Set)
  this.bindingSelectedIds = new Set(this.bindingSelectedIds);
}

// 保存绑定并关闭弹层
private async saveBinding(): Promise<void> {
  const shot = this.editingShotForBinding;
  if (!shot) {
    return;
  }
  const ids = [...this.bindingSelectedIds].sort((a, b) => a - b);
  this.editingShotForBinding = null;
  this.bindingSelectedIds = new Set();
  try {
    await UseCases.updateShotCharacterIds(shot.id, ids);
    promptAction.showToast({ message: `#${shot.shotNumber} 角色绑定已更新` });
  } catch (e) {
    promptAction.showToast({ message: '角色绑定保存失败,请重试' });
  }
  this.shots = await UseCases.getStoryboards(this.projectId);
}

// 取消绑定编辑
private cancelBindingEdit(): void {
  this.editingShotForBinding = null;
  this.bindingSelectedIds = new Set();
}
```

- [ ] **Step 5: 在 Step 4 方法之后新增 3 个 UI 构造方法**

这些是 struct 普通方法(返回 void),ArkUI 允许它们直接构造 UI 节点:

```ts
// 顶部"角色"行的副标题:"0 个" / "3 个" 等
private bindingSummary(shot: StoryboardShot): string {
  if (!shot.characterIds || shot.characterIds.trim().length === 0) {
    return '0 个';
  }
  let count = 0;
  try {
    const arr = JSON.parse(shot.characterIds) as Object;
    if (Array.isArray(arr)) {
      count = arr.length;
    }
  } catch (_e) { /* ignore */ }
  return `${count} 个`;
}

// 角色头像行:展示已绑角色的圆形头像(无图用首字母占位)+ 溢出数字徽标
private buildBindingAvatarsRow(shot: StoryboardShot): void {
  Row() {
    if (shot.characterIds === null || shot.characterIds.trim().length === 0) {
      Text('未绑定角色')
        .fontSize(13)
        .fontColor(Theme.textHint)
    } else {
      let ids: number[] = [];
      try {
        const arr = JSON.parse(shot.characterIds) as Object;
        if (Array.isArray(arr)) {
          for (let i = 0; i < arr.length; i++) {
            if (typeof arr[i] === 'number') {
              ids.push(arr[i] as number);
            }
          }
        }
      } catch (_e) { /* ignore */ }

      const idToChar = new Map<number, Character>();
      for (const ch of this.allCharacters) {
        idToChar.set(ch.id, ch);
      }
      const validIds = ids.filter(id => idToChar.has(id));
      const shown = validIds.slice(0, 3);
      const overflow = Math.max(0, validIds.length - 3);

      if (validIds.length === 0) {
        Text('绑定已失效,请重新编辑')
          .fontSize(13)
          .fontColor(Theme.textHint)
      } else {
        ForEach(shown, (id: number) => {
          this.buildBindingAvatar(idToChar.get(id)!)
        }, (id: number) => id.toString())
        if (overflow > 0) {
          Text(`+${overflow}`)
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
  }
  .width('100%')
}

// 单个角色头像(36x36 圆形):有图显示图片,无图显示首字母占位
private buildBindingAvatar(ch: Character): void {
  if (ch.imageLocalPath && ch.imageLocalPath.length > 0) {
    const src = ch.imageLocalPath.startsWith('file://')
      ? ch.imageLocalPath
      : `file://${ch.imageLocalPath}`;
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
```

- [ ] **Step 6: 新增 `buildCharacterPickCell` 弹层单格方法**

在 `buildBindingAvatar` 之后新增:

```ts
// 弹层里 2xN 网格中的单个角色可选卡片
private buildCharacterPickCell(ch: Character): void {
  const selected = this.bindingSelectedIds.has(ch.id);
  Column() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (ch.imageLocalPath && ch.imageLocalPath.length > 0) {
        const src = ch.imageLocalPath.startsWith('file://')
          ? ch.imageLocalPath
          : `file://${ch.imageLocalPath}`;
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
```

- [ ] **Step 7: 在分镜卡片 `formatMeta` 调用前插入角色卡片**

修改 build() 内 ListItem 块(line 147-180),在 `PromptCardBuilder('视频提示词', ...)` 之后、`Text(this.formatMeta(shot))` 之前,新增:

```ts
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

  this.buildBindingAvatarsRow(shot)
}
.padding(12)
.width('100%')
.backgroundColor('#1A000000')
.borderRadius(8)
.margin({ bottom: 10 })
```

- [ ] **Step 8: 在 `if (this.editingShot)` 块之后插入绑定编辑弹层**

参考 `CharacterListPage.ets:271-330` 的"遮罩 + 居中卡片"模式。在 `if (this.editingShot)` 块(line 189)之后,新增对称的绑定弹层块:

```ts
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
        Text('暂无可绑定角色,请先提取角色')
          .fontSize(14)
          .fontColor(Theme.textHint)
          .width('100%')
          .padding(20)
          .textAlign(TextAlign.Center)
      } else {
        Grid() {
          ForEach(this.allCharacters, (ch: Character) => {
            GridItem() {
              this.buildCharacterPickCell(ch)
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
```

- [ ] **Step 9: 编译验证**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
./hvigorw assembleHap
```

期望:`> hvigorw BUILD SUCCESSFUL`。Task 1 的 3 个方法 + Task 2 的 UI 同时编译通过。

- [ ] **Step 10: 提交**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/pages/StoryboardViewerPage.ets
git commit -m "feat(harmony): StoryboardViewerPage 角色绑定查看/编辑 UI"
```

提交信息体写明:
- 卡片结构:标题 → 图片提示词 → 视频提示词 → **角色(新)** → 元信息
- 角色行:角色名 + 数量徽标 + 编辑链接,下方是头像行(无图用首字母占位,3+ 显 +N)
- 编辑弹层:2 列角色网格,带选中边框与 ✓ 标记,预选解析双格式(number[] / name fallback),保存时统一写 number[] JSON
- `UseCases.updateShotCharacterIds` 在弹层保存时调用(由 Task 1 提供)
- 不动 ProjectDetailPage / CharacterListPage / 任何数据库 / 任何 Android 文件
- 下次点 ProjectDetailPage 的"生成图片"时 `buildCharacterReferences` 走快路径消费新绑定
