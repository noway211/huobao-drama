# 鸿蒙端分镜图片 prompt 角色绑定修复 设计

**状态:** 已批准
**日期:** 2026-08-13
**作者:** Claude (brainstorming + planning)
**前置 fix:** i2i base64 转换（commit `e674bef` 在 dev 分支）

## 背景与动机

### 现象

2026-08-13 用户报告：

> 现在发现角色的图片与提示词，与分镜里面提示词有冲突

具体场景：分镜 1 关联 2 个角色（北寒风、张红），传给 Agnes i2i 时 `extra_body.image` 数组有 2 张参考图，但 prompt 中描述"北寒风：白胡子老者... 张红：红衣女子..."，模型无法把第 1 张图对应"北寒风"还是"张红"——最终出图把红衣特征画到白发老者身上。

### 根因（一句话）

`UseCases.buildCharacterReferences` ([ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:803-878](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L803)) 在同一个 for 循环里**独立 push** `refs` 和 `charDescs`：

```ts
if (refUrl && refUrl.trim().length > 0) { refs.push(refUrl); }
if (ch.appearance && ch.appearance.trim().length > 0) {
  charDescs.push(`${ch.name}：${ch.appearance}`);
}
```

`referenceUrls[i]` 与 `characterText` 字符串中第 i 个角色**没有强制对应**。3 张图上限只对 `refs` 生效，prompt 文本可能描述比图片更多的角色（或反过来有图无描述）。

### 关键 API 约束

[Agnes 文档](https://agnes-ai.com/zh-Hans/docs/agnes-image-20-flash) 规定：

> `image` | `string[]` | 图生图必填 | 输入图像数组，支持公网 URL 或 Data URI Base64

——**`extra_body.image` 只接受字符串数组，不支持 per-image label/text/weight/name 字段**。文档里明确说"多图合成时，prompt 靠自然语言按顺序引用图片。最佳实践：'Place the person from the first image beside the robot from the second image...'"。

**结论**：唯一可行的角色↔图片绑定方式，是把"The person from reference image N is <Name>..."这句话写进顶层 `prompt` 字段。

## 设计目标

让 `referenceUrls[i]` 与 `characterText` 中第 i 个角色描述**严格一一对应**，并在 prompt 中以 "reference image N" 句式显式锚定第 N 张图。

## 设计方案

### 核心修复：atomic push

把循环里的两段独立 `if + push` 改成 **atomic guard**：refUrl 和 appearance 缺一就 `continue` 跳过该角色，**两个数组严格同步增长**。

### 统一 ID/Name 两条路径

现有代码 ID 路径和 Name 路径是分离的两个循环 + 各自的 result 构造。抽 `resolveCharacters(ids, allCharacters): Character[]` 辅助方法，把两条路径折叠成一条。

### 新 characterText 模板

```
The person in reference image 1 is 北寒风 (elderly scholar with long white beard). The person in reference image 2 is 张红 (young woman in red dress).
```

每行用 `refs.length` 作为索引（因为只在 push 后立即构造 desc line，所以索引 = refs.length 保证一一对应）。

## 失败处理语义

| 场景 | 行为 |
|---|---|
| `characterIds` 为空 / null / 非法 JSON | `characterText = ''`，prompt 原样用 `shot.imagePrompt`（与现有行为一致） |
| 角色有 appearance 但没 refUrl | atomic guard 跳过该角色，prompt 不描述它 |
| 角色有 refUrl 但没 appearance | atomic guard 跳过该角色，prompt 不描述它 |
| 5 角色但只有 3 个有完整字段 | 只描述 3 个，与图片数严格对齐 |
| 角色超过 3 个 | 仍按 3 张图上限（保持先前 SDD 硬约束） |
| 角色 ID/name 解析不到 | `resolveCharacters` 静默跳过 |

## 改动范围

| 文件 | 改动 | 行数估计 |
|---|---|---|
| `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets` | 改 docstring + 重写 `buildCharacterReferences` + 新增 `resolveCharacters` | +35/-75 |

**只动 1 个文件**。`frontend/` / `app/` / `backend/` / 其他 Harmony 文件全部不碰。

## 全局约束 (Global Constraints)

| 项 | 值 | 出处 |
|---|---|---|
| `CharacterRefInfo` 类型 | `{ referenceUrls: string[]; characterText: string }` | 现有 line 31-34 |
| `buildCharacterReferences` 签名 | `private static async (projectId, shot): Promise<CharacterRefInfo>` | 现有 line 803-806 |
| 3 张图上限 | `refs.length >= 3 break` | 先前 SDD 硬约束 |
| 兼容两种 characterIds 格式 | 数字 ID 数组 + 字符串名数组 | 现有 `parseCharacterIds` |
| 下游 concat site | `${charRef.characterText}${shot.imagePrompt}` | 现有 line 381-383 |
| 不动范围 | `parseCharacterIds`、`Character`/`StoryboardShot` 模型、`frontend/`、`backend/` | 约束 |

## 验证方式

### 编译层

```bash
cd ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap 2>&1 | tee /tmp/hvigor-prompt-fix.log
grep -E "ERROR:|BUILD FAILED" /tmp/hvigor-fix.log
```

预期：`0 hit`，`BUILD SUCCESSFUL`。

### 端到端（真机 hilog）

预期 hilog `generate image for shot N: prompt=... refs=M` 行的 `prompt=` 字段：

| 角色情况 | 预期 prompt 前缀 |
|---|---|
| 2 角色（都有 appearance + 图） | `The person in reference image 1 is 北寒风 (...). The person in reference image 2 is 张红 (...). <shot.imagePrompt>` |
| 1 角色 | `The person in reference image 1 is <Name> (...). <shot.imagePrompt>` |
| 0 角色 | `<shot.imagePrompt>`（原样） |
| 5 角色但只有 3 个有完整字段 | `... reference image 1/2/3 is ...`（3 条） |

## 关联

- 前置 fix：i2i base64 转换（commit `e674bef`）
- Agnes API 文档：https://agnes-ai.com/zh-Hans/docs/agnes-image-20-flash
- 后端等价实现：[backend/src/services/image-generation.ts](backend/src/services/image-generation.ts)（i2i 路径与本 fix 正交）
