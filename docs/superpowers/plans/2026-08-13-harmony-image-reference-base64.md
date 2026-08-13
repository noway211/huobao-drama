# 鸿蒙端分镜图参考图 base64 转换 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复鸿蒙端点击"生成图片" 500 错误——`AgnesImageRepository.generateImage` 把角色本地文件路径当 base64 直接发给 Agnes API，Agnes 解码失败。新建 `ImageReferenceResolver` helper 统一把 `local path / data URI / http(s) URL` 转换成合法 base64 data URI（与后端 `readImageAsCompressedDataUrl` 语义对齐：768×768 JPEG quality 68，失败逐图 skip + `hilog.warn` 不阻断整次）。

**Architecture:** Repository 层加一个纯函数 helper，无状态、无依赖注入；`AgnesImageRepository` 在发请求前 `Promise.all` 走一遍 resolver，过滤 null。UseCases 层不感知此转换。

**Tech Stack:** Harmony NEXT / ArkTS 严格模式 / `@kit.ImageKit`（imageSource/imagePacker） / `@kit.CoreFileKit`（fileIo） / `@ohos.util`（Base64Helper） / `@kit.PerformanceAnalysisKit`（hilog）

## Global Constraints

| 项 | 值 | 出处 |
|---|---|---|
| 压缩尺寸上限 | 768×768（`desiredSize`） | 后端 `image-generation.ts:206-209` |
| JPEG quality | 68 | 同上 |
| fit 模式 | `'INSIDE'`（保持比例，小图不放大） | 等价后端 `fit: 'inside', withoutEnlargement: true` |
| 输出格式 | `image/jpeg` | 后端强制 JPEG |
| EXIF 旋转 | `createPixelMap` 默认应用 | 等价后端 `.rotate()` |
| Alpha flatten | `ignoreAlpha: true` | 等价后端 `flatten({ background: '#ffffff' })`（已知限制：填黑非白） |
| 失败处理 | 逐图 skip + `hilog.warn`，不阻断整次 | 后端 `normalizeReferenceImages:212` |
| 全部失败回退 | `extra_body.image` 整个不设，走纯文生图 | 与后端一致 |
| 透传规则 | `data:` URI / `http://` / `https://` 直接透传 | 与后端一致 |
| 命名 | camelCase；DOMAIN = 0x0001；TAG = 'AgnesImageRepository' | 项目现有风格 |
| 不在范围 | 不动后端、不动 Vue、不动 `buildCharacterReferences` 的 3 张上限、不重写 i2i 调用结构 | spec §"不在范围" |
| 构建命令 | `cd ZdramaHarmony && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap` | 绝对路径，repo 不带 `./hvigorw` |
| 期望产物 | `BUILD SUCCESSFUL` | — |

---

## File Structure

| 状态 | 路径 | 职责 |
|---|---|---|
| 新建 | `ZdramaHarmony/entry/src/main/ets/remote/ImageReferenceResolver.ets` | 导出 `resolveImageReference(value: string): Promise<string \| null>`，1 个纯函数 + 内部 stage 标签用于日志 |
| 改 | `ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets` | +1 import + 改 1 个 if 块（line 87-89，5 行 → ~12 行） |
| 不动 | `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets` | `buildCharacterReferences` 继续传 `imageLocalPath`，resolver 在 repository 层消化 |

---

## Task 1: 实现 `ImageReferenceResolver.ets`

**Files:**
- Create: `ZdramaHarmony/entry/src/main/ets/remote/ImageReferenceResolver.ets`

**Interfaces:**
- Consumes: 一个 `string` 入参（可能是 `data:image/...;base64,...`、`http(s)://...`、或绝对文件路径）
- Produces: `Promise<string | null>` —— `null` 表示该入参无法解析为合法参考图

**Dependencies (Harmony kits):**
- `@kit.CoreFileKit` — `fileIo` (`statSync`, `openSync`, `readSync`, `closeSync`, `OpenMode.READ_ONLY`)
- `@kit.ImageKit` — `image` (`createImageSource`, `createPixelMap`, `imagePacker`)，命名空间 `image` 默认导出函数
- `@ohos.util` — `Base64Helper.encodeToStr`
- `@kit.PerformanceAnalysisKit` — `hilog`

### Steps

- [ ] **Step 1: 写空文件 + 顶部 imports**

```ts
// ZdramaHarmony/entry/src/main/ets/remote/ImageReferenceResolver.ets
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { Base64Helper } from '@ohos.util';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0001;
const TAG = 'AgnesImageRepository';

// 压缩参数（与后端 image-generation.ts:206-209 对齐）
const MAX_WIDTH = 768;
const MAX_HEIGHT = 768;
const JPEG_QUALITY = 68;

interface ResolveOptions {
  // 预留：未来若要支持自定义压缩参数，从这里传入
}

export async function resolveImageReference(
  value: string,
  _options?: ResolveOptions
): Promise<string | null> {
  // 占位：Step 2-5 实现
  return null;
}
```

预期：文件创建完成，编译不报错（函数体只 return null，类型对齐）。

- [ ] **Step 2: 实现透传分支（data URI / http URL）**

在 `resolveImageReference` 函数体里替换 `return null;` 为：

```ts
const trimmed = (value ?? '').trim();
if (trimmed.length === 0) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | value=<empty> stage=trim error=empty');
  return null;
}

if (trimmed.startsWith('data:')) {
  // 已经是 data URI，透传
  return trimmed;
}
if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
  // 远程 URL，Agnes 支持，透传
  return trimmed;
}

// 下一步：本地路径处理
return null;
```

预期：编译通过，3 种入参（data/http/其他）的逻辑分支已就位。

- [ ] **Step 3: 实现本地路径读取 + stat 校验**

在 `Step 2` 的 `// 下一步：本地路径处理` 注释后、`return null;` 之前插入：

```ts
// 1) 文件存在性 + 非空
let stat: fileIo.Stat;
try {
  stat = fileIo.statSync(trimmed);
} catch (err) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=statSync error=%{public}s',
    trimmed, (err as BusinessError).message);
  return null;
}
if (stat.size <= 0) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=statSync error=empty file',
    trimmed);
  return null;
}

// 2) 读文件
let buffer: ArrayBuffer;
let file: fileIo.File | null = null;
try {
  file = fileIo.openSync(trimmed, fileIo.OpenMode.READ_ONLY);
  buffer = fileIo.readSync(file.fd, stat.size);
} catch (err) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=readSync error=%{public}s',
    trimmed, (err as BusinessError).message);
  return null;
} finally {
  if (file) {
    try { fileIo.closeSync(file); } catch (_ignore) {}
  }
}

if (buffer.byteLength <= 0) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=readSync error=read 0 bytes',
    trimmed);
  return null;
}

// 下一步：解码 + 编码
return null;
```

预期：编译通过，文件读取 + 资源释放 (try/finally) 完整。

- [ ] **Step 4: 实现解码 + 缩放 + JPEG 编码**

在 `Step 3` 的 `// 下一步：解码 + 编码` 注释后、`return null;` 之前插入：

```ts
// 3) 解码 → PixelMap（desiredSize + INSIDE + ignoreAlpha + EXIF 旋转）
let pixelMap: image.PixelMap;
try {
  const imageSource = image.createImageSource(buffer);
  pixelMap = await imageSource.createPixelMap({
    desiredSize: { width: MAX_WIDTH, height: MAX_HEIGHT },
    fit: 'INSIDE',
    ignoreAlpha: true,
  });
  imageSource.release();
} catch (err) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=createPixelMap error=%{public}s',
    trimmed, (err as BusinessError).message);
  return null;
}

// 4) JPEG 编码
let jpegBuffer: ArrayBuffer;
try {
  jpegBuffer = await new Promise<ArrayBuffer>((resolve, reject) => {
    imagePackerApi(pixelMap)
      .then(resolve)
      .catch(reject);
  });
} catch (err) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=imagePacker error=%{public}s',
    trimmed, (err as BusinessError).message);
  pixelMap.release();
  return null;
}
pixelMap.release();

if (!jpegBuffer || jpegBuffer.byteLength <= 0) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=imagePacker error=empty output',
    trimmed);
  return null;
}

// 5) base64 编码
let base64: string;
try {
  base64 = Base64Helper.encodeToStr(new Uint8Array(jpegBuffer));
} catch (err) {
  hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=Base64Helper error=%{public}s',
    trimmed, (err as BusinessError).message);
  return null;
}

const sizeKB = Math.round((jpegBuffer.byteLength) / 1024);
hilog.info(DOMAIN, TAG, 'reference resolved | path=%{public}s jpegSizeKB=%{public}d base64LenKB=%{public}d',
  trimmed, sizeKB, Math.round(base64.length / 1024));
return `data:image/jpeg;base64,${base64}`;
```

并在文件顶部（`const JPEG_QUALITY = 68;` 后）加一个内部 helper：

```ts
// 包装 imagePacker.packing（callback 风格 → Promise 风格）
function imagePackerApi(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  return new Promise((resolve, reject) => {
    try {
      image.createImagePacker().packing(pixelMap, {
        format: 'image/jpeg',
        quality: JPEG_QUALITY,
      }, (err: BusinessError | null, data: ArrayBuffer) => {
        if (err) {
          reject(err);
        } else {
          resolve(data);
        }
      });
    } catch (syncErr) {
      reject(syncErr);
    }
  });
}
```

预期：编译通过；所有资源（file、pixelMap、imageSource）都有 release / close。

- [ ] **Step 5: 编译验证**

Run:
```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap 2>&1 | tail -30
```

Expected: `> hvigor BUILD SUCCESSFUL in ...` 末行，无 ArkTS 编译错误（`Error: 10505001 ArkTS Compiler Error` 之类）。

如果失败，最常见原因：
- `image.createImagePacker` 在新 SDK 里改名 → 用 `image.ImagePacker` 类静态方法查文档
- `Base64Helper.encodeToStr` API 签名变化 → 备选 `util.Base64Helper`
- `ignoreAlpha` 不是 `DecodingOptions` 的合法 key → 改用 `desiredPixelFormat: 'RGB_565'`（或保留 alpha，后续在 packing 时丢）

- [ ] **Step 6: 提交**

```bash
git add ZdramaHarmony/entry/src/main/ets/remote/ImageReferenceResolver.ets
git commit -m "feat(harmony): 新增 ImageReferenceResolver 统一处理 i2i 参考图

data URI / http(s) URL 透传；本地路径走 fileIo + ImageKit 读 → 解码 →
desiredSize 768x768 INSIDE ignoreAlpha 缩放 → imagePacker JPEG q68 →
Base64Helper 编码。失败逐图 hilog.warn + return null，镜像后端
normalizeReferenceImages 语义。"
```

---

## Task 2: 集成到 `AgnesImageRepository.generateImage`

**Files:**
- Modify: `ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets:1-7` (imports) + `:86-89` (if 块)

**Interfaces:**
- Consumes: 现状 `referenceImages: string[]` 入参不变
- Produces: `extra_body.image` 现在是经过 resolver 过滤后的 base64 data URI 数组

### Steps

- [ ] **Step 1: 加 import**

在 `AgnesImageRepository.ets` 第 7 行（最后一个 import，`TextResult` 那个）后追加：

```ts
import { resolveImageReference } from './ImageReferenceResolver';
```

- [ ] **Step 2: 替换 if 块**

把 `AgnesImageRepository.ets:85-89`：

```ts
    // 图生图：传入参考图 URLs
    if (referenceImages && referenceImages.length > 0) {
      extraBody.image = referenceImages;
    }
```

替换为：

```ts
    // 图生图：传入参考图 URLs（先转 base64 data URI / 透传 URL）
    if (referenceImages && referenceImages.length > 0) {
      const resolved = await Promise.all(
        referenceImages.map(item => resolveImageReference(item))
      );
      const valid = resolved.filter((v): v is string => !!v);
      if (valid.length > 0) {
        extraBody.image = valid;
      } else {
        hilog.warn(DOMAIN, TAG,
          'all %{public}d reference images failed to resolve, fall back to text-to-image',
          referenceImages.length);
      }
    }
```

预期改动：
- 1 行 import 新增
- 1 个 if 块从 3 行扩到 12 行
- 不改 `referenceImages` 入参类型
- 不改 `extraBody.image` 字段类型（仍是 `string[]`）
- 全部失败时 `extraBody.image` 不被赋值 → API 走纯文生图路径

- [ ] **Step 3: 编译验证**

Run:
```bash
cd /Users/peterzhu/workspace/AndroidStudioProjects/ai_work/huobao-drama/ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap 2>&1 | tail -30
```

Expected: `> hvigor BUILD SUCCESSFUL in ...` 末行。

如失败，检查 `import { resolveImageReference }` 路径是否正确（与 `AgnesImageRepository.ets` 同目录 `remote/`），检查 `extraBody.image` 类型（interface 已定义为 `string[]`）。

- [ ] **Step 4: 提交**

```bash
git add ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets
git commit -m "feat(harmony): 分镜图生成前先 resolveImageReference 把本地参考图转 base64

修复 bug: 之前 extraBody.image 直接传本地文件路径，Agnes API 按
base64 解码失败返回 500。改为先走 Promise.all → ImageReferenceResolver
→ filter valid → 才赋值给 extraBody.image。任一失败仅 hilog.warn，
全部失败时整个 extraBody.image 不传，回退纯文生图。"
```

- [ ] **Step 5: 真机端到端验证（人工）**

前置：
- 至少 1 个有完整角色立绘（`image_status = completed` 且 `image_local_path` 非空）的项目
- 设备已连电脑（`hdc list targets` 应至少 1 个 entry）
- 当前 dev 分支已 build 并安装到设备

**5.1 启动 hilog 抓取**（独立终端窗口）：
```bash
hdc shell hilog -t 2000 2>&1 | grep -E "AgnesImageRepository|image generation|reference" | tee /tmp/hb-harmony-img-test.log
```

**5.2 基线测试（happy path）**：
- 在设备上点"生成图片"
- 预期 hilog：
  - 1~3 条 `reference resolved | path=... jpegSizeKB=... base64LenKB=...`（INFO）
  - `API response code=200`
  - `image generation FAILED` 不出现

**5.3 部分失败测试**：
- 临时把 `characters` 表里 1 个角色的 `image_local_path` 改成 `/nonexistent.png`（用 sqlite3 或 Harmony 调试入口）
- 再点"生成图片"
- 预期 hilog：
  - 1 条 `reference resolved`（INFO）+ 1 条 `reference resolve failed | stage=statSync`（WARN）
  - `API response code=200`（仍能生成）

**5.4 全失败回退测试**：
- 把所有角色 `image_local_path` 都改成不存在的路径
- 点"生成图片"
- 预期 hilog：
  - N 条 `reference resolve failed`（WARN）
  - 1 条 `all N reference images failed to resolve, fall back to text-to-image`（WARN）
  - `API response code=200`（纯文生图仍能成）

**5.5 收尾**：
- 恢复所有测试用的临时 `image_local_path` 改动
- 确认 `git status frontend/ app/` **无 diff**（核心约束：只动鸿蒙端，不动 Vue / 后端）

- [ ] **Step 6: 提交验证记录（如果需要）**

如果 5.2-5.5 有任何 hilog 输出值得存档（特别是失败用例的 WARN），把 `/tmp/hb-harmony-img-test.log` 里关键 5~10 行贴到 SDD 的 progress.md（不放进 commit），作为 fix-loop 的"Phase 1 验证证据"。

不强制 commit 日志（hilog 是设备侧 runtime 输出，不属于代码改动）。

---

## Self-Review

### 1. Spec coverage

- ✅ 现状 5xx 根因（spec §"根因"）— Plan 不需要复述，Task 1-2 实现即可
- ✅ 转换语义（spec §"转换语义"）— Task 1 Steps 2-4 完整覆盖
- ✅ 失败处理（spec §"失败处理语义"）— Task 1 Step 3/4 的 `try/catch` + `hilog.warn` + `return null`
- ✅ 全部失败回退（spec §"全部失败回退"）— Task 2 Step 2 的 `if (valid.length > 0)`
- ✅ 透传规则（spec §"输入 → 输出"）— Task 1 Step 2
- ✅ 压缩参数（spec §"压缩参数"）— Task 1 Step 4 + 顶部常量
- ✅ 日志规范（spec §"日志规范"）— Task 1 Steps 3-4 + Task 2 Step 2 都有 hilog
- ✅ 改动范围（spec §"改动范围"）— Plan 严格限定 2 个文件
- ✅ 验证方式（spec §"验证方式"）— Task 2 Step 5 全部覆盖

### 2. Placeholder scan

- 无 "TBD" / "TODO" / "待定" / "实现细节见..." 占位符
- 无 "Add appropriate error handling" 类空话（每条 try/catch 都给出具体 stage 名）
- 无 "Similar to Task N" 复用（Task 1-2 各自独立可读）

### 3. Type consistency

- `resolveImageReference(value: string): Promise<string | null>` 在 Task 1 定义
- Task 2 Step 2 的 `resolved.filter((v): v is string => !!v)` 类型守卫正确
- `extraBody.image: string[]` 类型未改，合法（data URI / http URL 都是 string）
- DOMAIN/TAG 在 Task 1 文件内定义（0x0001 / 'AgnesImageRepository'）与 `AgnesImageRepository.ets:8-9` 一致

### 4. 实施可行性自检

⚠️ **潜在的 Harmony API 风险点**（实施时如遇，按 Task 1 Step 5 提示回退）：

1. `image.createImagePacker` vs `image.ImagePacker` 静态方法 — 不同 SDK 版本 API 形态可能不同
2. `Base64Helper.encodeToStr` vs `util.Base64Helper.encodeToStr` — `@ohos.util` vs `@kit.ArkTS` 模块归属
3. `ignoreAlpha` 是 `DecodingOptions` 的合法 key — 部分版本需要 `desiredPixelFormat: image.PixelMapFormat.RGB_565`
4. `imageSource.release()` 是否需要 — 老版本 imageSource 不需要显式 release

子代理在 Task 1 Step 5 编译失败时，按以下顺序回退：
- 失败 1 → 查 Harmony NEXT 文档（`@kit.ImageKit` 章节），确认 API 签名
- 失败 2 → 用 Plan B：`util.TextDecoder` + 手写 base64 编码
- 失败 3 → 移除 `ignoreAlpha`，在 `imagePacker` 端用 `format: 'image/jpeg'` 天然丢 alpha
- 失败 4 → 移除 `imageSource.release()`，不 release 也行

如果 3 个以上回退都用尽，**升级模型并附 Phase 1 编译输出**。
