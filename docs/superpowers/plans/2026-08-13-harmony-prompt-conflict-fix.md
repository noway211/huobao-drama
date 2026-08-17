# 鸿蒙端分镜图片 prompt 角色绑定修复 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 `buildCharacterReferences` 中 `referenceUrls` 与 `characterText` 数组错位 bug，让 prompt 通过 "reference image N" 句式把 i2i 多参考图与角色名严格一一绑定。

**Architecture:** 单文件改动 `UseCases.ets`，atomic push 替代独立 push，抽 `resolveCharacters` 辅助方法统一 ID/Name 两条路径。

**Tech Stack:** ArkTS strict typing，hilog，纯本地文件改动（无新依赖）。

## Global Constraints

| 项 | 值 | 出处 |
|---|---|---|
| `CharacterRefInfo` 类型 | `{ referenceUrls: string[]; characterText: string }` | [UseCases.ets:31-34](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L31) |
| `buildCharacterReferences` 签名 | `private static async (projectId, shot): Promise<CharacterRefInfo>` | 保持不变 |
| 3 张图上限 | `refs.length >= 3 break` | 先前 SDD 硬约束 |
| 兼容两种 characterIds 格式 | 数字 ID 数组 + 字符串名数组 | 现有 `parseCharacterIds` |
| 下游 concat site | `${charRef.characterText}${shot.imagePrompt}` | [UseCases.ets:381-383](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L381) **不动** |
| 不动范围 | `parseCharacterIds`、`Character`/`StoryboardShot` 模型、`frontend/`、`backend/`、其他 Harmony 文件 | 约束 |

---

### Task 1: 重写 `buildCharacterReferences`，新增 `resolveCharacters`

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:796-878`（docstring + 函数体）
- Modify: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:880-901` 之后（新增 `resolveCharacters` 辅助方法）
- Reference（不修改）: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:380-386`（下游 concat site + hilog）
- Reference（不修改）: `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:880-901`（`parseCharacterIds` 保留）

**Consumes:**
- `Character` 模型 ([model/DramaModels.ets:131-146](ZdramaHarmony/entry/src/main/ets/model/DramaModels.ets#L131))：`id`, `name`, `appearance`, `imageUrl`, `imageLocalPath`
- `StoryboardShot.characterIds` JSON 字符串（`[1, 2]` 或 `["Alice", "Bob"]`）
- `UseCases.repo.getCharacters(projectId)` 已有方法
- `UseCases.hasNonEmptyLocalFile(path)` 已有方法（[UseCases.ets:66-75](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L66)）
- `UseCases.parseCharacterIds(ids)` 已有方法（[UseCases.ets:880-901](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L880)）

**Produces:**
- `CharacterRefInfo { referenceUrls: string[]; characterText: string }`（类型不变）
- `characterText` 新格式：`"The person in reference image 1 is <Name> (<Appearance>). The person in reference image 2 is ..."`

- [ ] **Step 1: 替换 docstring (lines 796-802)**

把现有 "分镜图片生成时注入角色参考图..." 替换为：

```ts
/**
 * 收集分镜关联角色的参考图，并为每张参考图生成"reference image N"绑定前缀。
 * characterText 中每条形如 "The person in reference image N is <Name> (<Appearance>)."
 * 与 referenceUrls[N-1] 一一对应，弥补 extra_body.image 不支持 per-image 标签的 API 限制。
 * characterIds 兼容数字 ID 数组与角色名字符串数组两种格式。
 */
```

- [ ] **Step 2: 重写 `buildCharacterReferences` 函数体（lines 803-878）**

完整替换为：

```ts
private static async buildCharacterReferences(
  projectId: number,
  shot: StoryboardShot
): Promise<CharacterRefInfo> {
  const refs: string[] = [];
  const descLines: string[] = [];

  const allCharacters = await UseCases.repo.getCharacters(projectId);
  if (allCharacters.length === 0) {
    return { referenceUrls: [], characterText: '' };
  }

  // 统一 ID/Name 两条路径：优先按数字 ID 查表，回退到字符串名查表
  const resolved: Character[] = UseCases.resolveCharacters(shot.characterIds, allCharacters);

  for (const ch of resolved) {
    if (refs.length >= 3) break;

    const refUrl = (ch.imageLocalPath && UseCases.hasNonEmptyLocalFile(ch.imageLocalPath))
      ? ch.imageLocalPath
      : (ch.imageUrl ?? undefined);

    // Atomic push：refUrl 与 appearance 缺一就跳过该角色，避免数组错位
    if (!refUrl || refUrl.trim().length === 0) continue;
    if (!ch.appearance || ch.appearance.trim().length === 0) continue;

    refs.push(refUrl);
    descLines.push(`The person in reference image ${refs.length} is ${ch.name} (${ch.appearance}).`);
  }

  const characterText = descLines.length > 0 ? descLines.join(' ') + '\n' : '';
  return { referenceUrls: refs, characterText };
}
```

- [ ] **Step 3: 新增 `resolveCharacters` 辅助方法（紧接 `parseCharacterIds` 之后）**

在 `parseCharacterIds` 函数（line 901 结尾 `}` 之后、`remapCharacterNamesToIds` 之前），新增：

```ts
/**
 * 将 shot.characterIds 解析为 Character[]。优先按数字 ID 查表，回退到字符串名查表。
 * 未匹配的 ID/name 静默跳过。空输入返回 []。
 */
private static resolveCharacters(
  ids: string | null | undefined,
  allCharacters: Character[]
): Character[] {
  if (allCharacters.length === 0) return [];

  // 路径 1：按数字 ID 查表
  const numericIds = UseCases.parseCharacterIds(ids);
  if (numericIds.length > 0) {
    const charMap = new Map<number, Character>();
    for (const ch of allCharacters) charMap.set(ch.id, ch);
    const out: Character[] = [];
    for (const id of numericIds) {
      const ch = charMap.get(id);
      if (ch) out.push(ch);
    }
    if (out.length > 0) return out;
  }

  // 路径 2：按字符串名查表（fallback）
  let names: string[] = [];
  try {
    const arr: Object = JSON.parse(ids ?? '[]');
    if (Array.isArray(arr)) {
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string') {
          names.push(arr[i] as string);
        }
      }
    }
  } catch (_e) { /* ignore */ }

  if (names.length === 0) return [];

  const nameMap = new Map<string, Character>();
  for (const ch of allCharacters) nameMap.set(ch.name, ch);
  const out: Character[] = [];
  for (const name of names) {
    const ch = nameMap.get(name);
    if (ch) out.push(ch);
  }
  return out;
}
```

- [ ] **Step 4: 验证编译**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap 2>&1 | tee /tmp/hvigor-prompt-fix.log
grep -E "ERROR:|BUILD FAILED" /tmp/hvigor-prompt-fix.log
```

预期：0 hit，BUILD SUCCESSFUL。

**关键校验**：必须用 `grep -E "ERROR:|BUILD FAILED"`，**不能只看末行 `> hvigor BUILD SUCCESSFUL`**——前 4 轮 i2i fix 的 implementer 全栽在这上面。

- [ ] **Step 5: 验证下游 concat site 未受影响**

读 `UseCases.ets:380-386` 确认：

```ts
const charRef: CharacterRefInfo = await UseCases.buildCharacterReferences(projectId, shot);
const enrichedPrompt = charRef.characterText.length > 0
  ? `${charRef.characterText}${shot.imagePrompt}`
  : shot.imagePrompt;
hilog.info(DOMAIN, TAG, 'generate image for shot %{public}d: prompt=%{public}s refs=%{public}d',
  shot.shotNumber, enrichedPrompt, charRef.referenceUrls.length);
```

应原样不动。

- [ ] **Step 6: Commit**

```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama
git add ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets
git commit -m "fix(harmony): atomic push in buildCharacterReferences, bind reference image N to character N"
```
