# 鸿蒙端角色图片支持删除 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `CharacterListPage.ets` 给每个有图片的角色加「删除图片」入口，软删除（DB status 置 PENDING + 清字段 + 删本地文件），让用户可以重新生成。

**Architecture:** 复用已有的 `UseCases.repo.updateCharacterImage(...)` 做软删除（已在 `CharacterLocalDataSource.ets:114`），用 `fileIo.unlinkSync` 删本地文件；UI 上在原「编辑提示词 / 生成图片」按钮行下方新起一行，右对齐小「删除图片」按钮，点击弹 `promptAction.showDialog` 二次确认；仅当 `ch.imageStatus === AssetStatus.COMPLETED` 时显示。完全镜像 `2026-08-13-harmony-viewer-delete-assets` SDD 的模式。

**Tech Stack:** HarmonyOS NEXT · ArkTS · ArkUI · `@kit.CoreFileKit.fileIo` · `@kit.ArkUI.promptAction` · relationalStore（不动）。

## Global Constraints

| 项 | 值 |
|---|---|
| `UseCases.repo` 访问性 | 保持 `private static` |
| `CharacterLocalDataSource.updateCharacterImage` 签名 | 不动（已存在，line 114） |
| 数据库 schema / model enum | 不动 |
| 二次确认 | `promptAction.showDialog` |
| 删除按钮样式 | `Theme.surfaceAlt` 背景 + `Theme.textPrimary` 文字 |
| 删本地文件容错 | `try-catch + hilog.warn`，不 throw |
| 不动范围 | `frontend/`、`app/`、`backend/`、`CharacterLocalDataSource.ets`、`model/DramaModels.ets` |

---

### Task 1: 新增 `UseCases.updateCharacterImage` public wrapper

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:200-203`（紧接 `updateCharacterAppearance` 之后插入）

**Consumes:**
- `UseCases.repo.updateCharacterImage(characterId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage): Promise<void>` 已有方法（[CharacterLocalDataSource.ets:114-132](ZdramaHarmony/entry/src/main/ets/data/CharacterLocalDataSource.ets#L114)）

**Produces:**
- `UseCases.updateCharacterImage(characterId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage): Promise<void>` 1 行透传

- [ ] **Step 1: 插入新 wrapper**

在 `UseCases.ets:203` `updateCharacterAppearance` 函数体的 `}` 之后插入：

```ts
/** 更新单个角色的图片生成结果（imageStatus / url / localPath / errorMessage）。 */
static async updateCharacterImage(
  characterId: number,
  imageStatus: AssetStatus,
  imageUrl: string | null,
  imageLocalPath: string | null,
  imageErrorMessage: string | null
): Promise<void> {
  await UseCases.repo.updateCharacterImage(characterId, imageStatus, imageUrl, imageLocalPath, imageErrorMessage);
}
```

- [ ] **Step 2: 验证编译（先于 Task 2）**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap 2>&1 | tee /tmp/hvigor-char-delete.log
grep -E "ERROR:|BUILD FAILED" /tmp/hvigor-char-delete.log
echo "---END GREP---"
```

预期：0 hit（grep 输出为空）。**必须 grep，不只看末行**。

- [ ] **Step 3: Commit Task 1（独立 commit）**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets
git commit -m "feat(harmony): add UseCases.updateCharacterImage public wrapper"
```

---

### Task 2: 在 `CharacterListPage.ets` 加「删除图片」按钮 + 处理器

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/pages/CharacterListPage.ets:116` 之后（新增 `onDeleteCharacterImageClick` 方法）
- Modify: `ZdramaHarmony/entry/src/main/ets/pages/CharacterListPage.ets:254-256` 之间（在卡片 Column 内、原按钮行之后插入新 Row）

**Consumes:**
- `UseCases.updateCharacterImage`（Task 1 新增）
- `fileIo.unlinkSync` 已在 line 3 引用
- `promptAction.showDialog` 已在 line 1 引用
- `Theme.surfaceAlt` / `Theme.textPrimary` 已在 line 7 引用
- `AssetStatus.PENDING` 用于软删目标状态

**Produces:**
- UI 变更：原 2 按钮卡片下方多一行右对齐「删除图片」按钮
- 新方法 `private async onDeleteCharacterImageClick(ch: Character): Promise<void>`

- [ ] **Step 1: 新增 `onDeleteCharacterImageClick` 方法**

紧接 `onGenerateImage` 方法（line 116 结尾 `}` 之后）插入：

```ts
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
```

- [ ] **Step 2: 在卡片 UI 中新增「删除图片」按钮行**

在 `CharacterListPage.ets:254`（原按钮 Row `}` 之后、`.width('100%')` 之后），`.padding(16)` 之前，插入：

```ts
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
```

- [ ] **Step 3: 验证编译**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap 2>&1 | tee /tmp/hvigor-char-delete.log
grep -E "ERROR:|BUILD FAILED" /tmp/hvigor-char-delete.log
echo "---END GREP---"
```

预期：0 hit，BUILD SUCCESSFUL。

- [ ] **Step 4: 验证未触范围**

- `frontend/` / `app/` / `backend/` 文件无任何修改
- `CharacterLocalDataSource.ets` 不动
- `Character` / `AssetStatus` model 不动
- 原「编辑提示词 / 生成图片」按钮行不动
- `reloadCharacters` / `onGenerateImage` / `startEdit` 等方法不动

- [ ] **Step 5: Commit Task 2**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/pages/CharacterListPage.ets
git commit -m "feat(harmony): add character image delete button in CharacterListPage"
```
