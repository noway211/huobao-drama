# 鸿蒙端角色图片支持删除 设计

**状态:** 已批准
**日期:** 2026-08-13
**作者:** Claude (brainstorming + planning)
**前置 SDD:** `harmony-viewer-delete-assets`（commit `0dfde93`）—— 同一套模式扩展到角色立绘

## 背景与动机

### 现象

2026-08-13 用户提出"角色图片也支持删除"——之前的 `harmony-viewer-delete-assets` SDD 实现了分镜图片/视频/成片的删除，但**角色立绘**没覆盖。用户无法清空错误生成的角色图重新生成。

### 根因（一句话）

`CharacterListPage.ets` 当前只有「编辑提示词」和「生成图片」两个按钮，没有删除入口。`UseCases.updateCharacterAppearance`（[UseCases.ets:201-203](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L201)）wrapper 存在，但**没有** `UseCases.updateCharacterImage` wrapper，UI 页面无法直接调 `UseCases.repo.updateCharacterImage`（repo 是 `private static`，[UseCases.ets:41](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L41)）。

### 复用基础

- `CharacterLocalDataSource.updateCharacterImage` (line 114) 已有——可作软删除
- `StoryboardImagePage.onDeleteImageClick` 模式已存在（viewer-delete-assets）—— 直接镜像
- `fileIo.unlinkSync` / `promptAction.showDialog` / `Theme.surfaceAlt` 全部已在 CharacterListPage 引用过

## 设计目标

在 `CharacterListPage.ets` 给每个有图片的角色加「删除图片」入口，软删除（DB status 置 PENDING + 清字段 + 删本地文件），让用户可以重新生成。

## 设计方案

### UX

- **按钮位置**：在原「编辑提示词 / 生成图片」按钮行下方新起一行，右对齐小按钮（与 viewer delete 模式一致）
- **按钮文案**：「删除图片」
- **可见性**：`if (ch.imageStatus === AssetStatus.COMPLETED)`——没图不显示
- **二次确认**：`promptAction.showDialog` title="删除角色图片？"，buttons `[{取消}, {删除图片}]`
- **删除后反馈**：toast "已删除" + 自动 reload 列表

### 软删除语义

```ts
UseCases.updateCharacterImage(ch.id, AssetStatus.PENDING, null, null, null);
// + 容错 unlink 本地文件
```

### 完整代码（已在 plan 里）

见 `docs/superpowers/plans/2026-08-13-harmony-character-image-delete.md`。

## 改动范围

| 文件 | 改动 | 行数估计 |
|---|---|---|
| `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets` | 新增 `updateCharacterImage` public wrapper | +6 |
| `ZdramaHarmony/entry/src/main/ets/pages/CharacterListPage.ets` | 新增「删除图片」按钮行 + `onDeleteCharacterImageClick` 方法 | +40 |

**只动 2 个文件，~46 行 diff**。

## 全局约束

| 项 | 值 | 出处 |
|---|---|---|
| `UseCases.repo` 访问性 | 保持 `private static` | 现有 line 41 |
| `CharacterLocalDataSource.updateCharacterImage` 签名 | 不动 | 现有 line 114 |
| 数据库 schema / model enum | 不动 | 软删复用 `AssetStatus.PENDING` |
| 二次确认 | `promptAction.showDialog` | 现有 `Index.ets` 模式 |
| 删除按钮样式 | `Theme.surfaceAlt` 背景 + `Theme.textPrimary` 文字 | 现有 viewer delete 模式 |
| 删本地文件容错 | `try-catch + hilog.warn` | viewer-delete-assets 模式 |
| 不动范围 | `frontend/`、`app/`、`backend/`、`CharacterLocalDataSource.ets`、`model/DramaModels.ets` | 约束 |

## 验证方式

### 编译层

```bash
cd ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap 2>&1 | tee /tmp/hvigor-char-delete.log
grep -E "ERROR:|BUILD FAILED" /tmp/hvigor-char-delete.log
```

预期：0 hit，BUILD SUCCESSFUL。

### 端到端（真机）

1. 项目有 3 个角色（A 已生成图、B 已生成图、C 未生成图）
2. 进角色列表页 → A、B 卡片底部有「删除图片」按钮，C 没有
3. 点 A「删除图片」→ 弹「删除角色图片？」→ 确认
4. toast "已删除"，A 卡片头像变 placeholder
5. 重新点 A「生成图片」正常重新生成
6. 查 DB：`characters` 表 A 的 `image_status` = `PENDING`，`image_url` / `image_local_path` / `image_error_message` = NULL
7. 查本地：`filesDir/generated/{projectId}/char_{a.id}_image.*` 文件没了
8. 容错测试：把 A 的 `imageLocalPath` 改成 `/nonexistent/path/xxx.jpg`，点删除 → 仍成功（toast "已删除"）

## 关联

- 前置 SDD：`2026-08-13-harmony-viewer-delete-assets`（commit `0dfde93`）—— 同一套模式
- 复用：`CharacterLocalDataSource.updateCharacterImage` (line 114)、`UseCases.updateCharacterAppearance` wrapper 模式 (line 201-203)
- 无关：i2i base64 fix (e674bef)、prompt conflict fix (78f579b)
