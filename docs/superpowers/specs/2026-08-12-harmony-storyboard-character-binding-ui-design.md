# 鸿蒙端分镜角色绑定 UI — 设计文档

> 日期: 2026-08-12
> 范围: HarmonyOS 端 `ZdramaHarmony/`
> 前置: 角色提取 + 角色图生成 + 分镜生成 + 分镜图片生成 链路已全部就位

## Context

### 现状

鸿蒙端已经具备完整的"角色 → 分镜 → 分镜图"生成链路,数据层 `Shot.characterIds: string | null`(JSON 字符串,存数字 ID 数组)在 `generateStoryboardImages` 流程里已经被 `UseCases.buildCharacterReferences()` 读取,作为图片生成的参考图与外貌描述来源(最多 3 个角色)。

但**整条链路对用户不可见**:
- 用户在 `CharacterListPage` 看到角色、生成角色图
- 用户在 `StoryboardViewerPage` 看分镜、编辑提示词
- **用户从不知道哪些角色绑到了哪个分镜上,也没有入口调整绑定**
- `UseCases.remapCharacterNamesToIds()` 函数**已定义但从未被调用** — LLM 返回的 `character_names` 字符串数组始终停留在 `characterIds` 字段,靠 `buildCharacterReferences` 的 name-fallback 兜底匹配

### 目标

让"分镜绑角色"这件事在 UI 层可见、可调:
- 在 `StoryboardViewerPage` 每个分镜卡片展示**已绑角色的头像** + 数量徽标
- 提供"编辑"入口,弹出**全项目角色多选器**,预选当前绑定(兼容 LLM 推测 + 已是 ID 两种格式)
- 保存后 `Shot.characterIds` 写入**规范的 number[] JSON**(例如 `"[1, 3, 5]"`)
- 不增加新的"重生成"入口 — 用户改完绑定,下次点 `ProjectDetailPage` 的"生成图片"时自然用新绑定

## Design

### 数据契约

`StoryboardShot.characterIds: string | null` 字段语义统一为 **number[] JSON**:
- 之前 LLM 直接写入的字符串数组(`["Alice", "Bob"]`)在 UI 读出后会被**展示层解析**为预选 ID;不主动改写老数据
- 之后用户保存时,无论预选来源是 ID 还是 name,落盘都写成 number[] JSON(`"[1, 3]"`)

这一约定不破坏现有 `buildCharacterReferences` 的双格式兼容 — 它会先尝试按 ID 解析,失败后按 name 解析,新格式走快速路径,老格式走 fallback。

### 入口与 UI 形态

#### `StoryboardViewerPage` 卡片结构变更

每个分镜卡片(`#shotNumber scene`)在"图片提示词"和"视频提示词"提示词卡片**之间**(因为分镜图生成最依赖角色,放在视觉相关位置),新增一个 **"角色" 卡片**:

```
┌─ #1 场景描述 ───────────────────────┐
│ 图片提示词  …            [点击编辑]│
│ 角色      [头像][头像][+2]   [编辑] │  ← 新增
│ 视频提示词  …            [点击编辑]│
│ 动作/对白/镜头/时长                    │
└──────────────────────────────────────┘
```

展示规则:
- 有 0 个角色 → 显示"未绑定角色"+ "编辑"链接
- 有 1-3 个角色 → 显示角色头像(无图则首字母圆形占位)+ 名字
- 有 3+ 个角色 → 头像 + "…" + 数字徽标(例如 `+2`)
- 点"编辑" → 弹多选弹层

#### 多选弹层

```
┌─ 编辑 #1 角色绑定 ─────────────────┐
│ 已选 2 个: Alice, Bob               │
│ ┌─────────────┐ ┌──────────────┐   │
│ │ ☑ Alice     │ │ ☐ Carol      │   │
│ │   [头像]    │ │   [头像]     │   │
│ │   主角      │ │   配角       │   │
│ └─────────────┘ └──────────────┘   │
│ … 更多角色 2×3 网格 …                │
│                                     │
│  [取消]            [保存]           │
└─────────────────────────────────────┘
```

预选规则(打开弹层时):
1. 先尝试 `parseCharacterIds(shot.characterIds)` → number[] → 预选这些 ID
2. 若解析为空,尝试解析为 string[] (LLM 返回的 names) → 按 name 查角色 → 预选这些 ID
3. 都没匹配到 → 默认空选

保存规则(点保存时):
- 把当前选中的 number[] 序列化为 JSON 字符串写入 `characterIds`
- 取消 → 不写库,关闭弹层

### 数据层改动

#### `StoryboardLocalDataSource.ets`

新增方法,参照 `updateShotImagePrompt` 的查询模式:

```ts
async updateStoryboardCharacterIds(
  shotId: number,
  characterIdsJson: string
): Promise<void>
```

实现:`UPDATE storyboards SET character_ids = ?, updated_at = ? WHERE id = ?`

#### `DramaRepository.ets`

新增转发方法:

```ts
async updateStoryboardCharacterIds(
  shotId: number,
  characterIdsJson: string
): Promise<void>
```

#### `UseCases.ets`

新增 1 个公开静态方法:

```ts
/**
 * 写回分镜的角色绑定(规范化为 number[] JSON)。
 * 接受 number[],内部 JSON.stringify 后存库;空数组传 null 入库。
 */
static async updateShotCharacterIds(
  shotId: number,
  characterIds: number[]
): Promise<void>
```

不在 UseCases 里加"重生成"或"重映射"路径。`remapCharacterNamesToIds` 仍保持已定义但未调用(老数据靠 `buildCharacterReferences` 的 name-fallback 兜底)。

### 触发"重新生成"流程

**不在本次实现范围内**。用户改完绑定后,点 `ProjectDetailPage` 的"生成图片"全量按钮,会走 `UseCases.generateStoryboardImages`,内部 `buildCharacterReferences` 会用新的 `characterIds` 注入参考图。

如未来需要"重生成单分镜图片",单独写任务。

## File-by-file plan

| 文件 | 改动 |
|---|---|
| `ZdramaHarmony/entry/src/main/ets/data/StoryboardLocalDataSource.ets` | + `updateStoryboardCharacterIds()` 方法(~12 行) |
| `ZdramaHarmony/entry/src/main/ets/data/DramaRepository.ets` | + 转发方法(~3 行) |
| `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets` | + `updateShotCharacterIds()` 静态方法(~10 行) |
| `ZdramaHarmony/entry/src/main/ets/pages/StoryboardViewerPage.ets` | + 角色卡片 + 多选弹层(~150 行,含样式) |
| 数据库 | 不变 |
| `ProjectDetailPage.ets` | 不变 |
| `CharacterListPage.ets` | 不变 |

## 边界与不做什么

**不做的**:
- ❌ 不调 `UseCases.remapCharacterNamesToIds` 把 LLM 字符串数组主动转 ID(老数据已用 name-fallback 兜底,UI 层预选解析时也兼容)
- ❌ 不加"重新生成本分镜图片"入口(用户走 `ProjectDetailPage` 全量按钮)
- ❌ 不动 `module.json5` / EntryAbility / 任何 lifecycle 代码
- ❌ 不写新表 / 不加字段
- ❌ 不动 Android 端
- ❌ 不重构 `buildCharacterReferences`(它已经处理 ID + name 双格式,本次 UI 写的 number[] JSON 会走快路径)

**做的**:
- ✅ 让用户**看见**绑定(头像 + 名字 + 数量徽标)
- ✅ 让用户**调整**绑定(多选弹层,预选当前绑定)
- ✅ 让用户**保存**绑定(写 number[] JSON)

## 验证

### 静态

- 编译 `hvigorw assembleHap` 通过(无新增 SDK API,只动 UI/数据层)
- 新增的 `updateStoryboardCharacterIds` 与现有 `updateShotImagePrompt` / `updateShotVideo` 风格一致

### 端到端(需真机)

1. 进入一个**已提取角色 + 已生成分镜**的项目
2. `StoryboardViewerPage` 每个分镜卡片显示"角色"行,展示 LLM 推测的绑定(可能为空、可能有 name 也有 ID)
3. 点 "编辑" → 弹多选弹层
4. 看到**预选状态**与卡片头像一致
5. 勾选/取消若干角色 → 点"保存"
6. 弹层关闭,卡片头像更新
7. 退出回到 `ProjectDetailPage` → 点"生成图片"
8. 新生成的图片角色外观与编辑后的绑定一致(参考图正确传入)

### 边界场景

- 没有任何角色:角色卡片显示"未绑定角色","编辑"链接点击后弹层显示"暂无可绑定角色,请先提取角色"
- 没有任何分镜:不进入此页面(已有保护)
- `characterIds` 是 `[1, 2, 3]` 但角色已被删除:预选时跳过不存在的 ID(查不到则忽略),展示只显示有效角色
- `characterIds` 是 LLM 字符串 name 但项目里没匹配角色:不预选,空状态开始

## 风险

- **小**: 改 `characterIds` 字段,影响 `buildCharacterReferences` 的快/慢路径,新格式走快路径(name-fallback 失去被使用机会)。等价于把"软绑定"变成"硬绑定" — 改名/删角色后,旧绑定可能对不上名字导致失效。但这是改善,不是回归:用户能主动调整即恢复
- **无**: 不动生成逻辑、不动数据库 schema、不动 lifecycle

## 后续可选(不在本次实现)

- `ProjectDetailPage` 顶部加一个"已绑定角色 X / Y"的统计(信息性,非阻塞)
- `StoryboardViewerPage` 角色卡片加"快速重生成"按钮(单分镜粒度)
- 自动在生成图片之前调一次 `remapCharacterNamesToIds` 清理老数据(迁移用,不是功能)
