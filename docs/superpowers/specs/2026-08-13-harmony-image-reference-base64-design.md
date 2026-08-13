# 鸿蒙端分镜图参考图 base64 转换 设计

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this design task-by-task.

**状态:** 已批准
**日期:** 2026-08-13
**作者:** Claude (brainstorming)
**关联 commit:** —

## 背景与动机

### 现象

2026-08-13 用户在鸿蒙端点击"生成图片"，收到 hilog 错误：

```
08-13 14:23:56.785  image generation FAILED for shot #1:
  HTTP 500: {
    "error": {
      "message": "upload image queue input image[0]: illegal base64 data at input byte 0 (request id: 20260813062356472128983fC6qK7o1)",
      "type": "AgnesAI_error",
      "param": "",
      "code": "convert_request_failed"
    }
  }
```

### 根因（一句话）

`AgnesImageRepository.generateImage` ([ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets:87-89](ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets#L87)) 把 `referenceImages` 数组（元素为角色本地文件路径如 `/data/app/el2/100/base/com.huobao.zdrama/files/generated/3/char_8_image.png`）原封不动塞进 `extra_body.image` 字段发给 Agnes API。Agnes 服务端把每个元素当作 base64 解码——遇到路径字符串以字母 `s`（来自 `static/`）开头，第 0 个字节不是合法 base64 字符 → 整个请求 500 失败。

### 对照：Vue 前端 + 后端不踩这个坑

Vue 前端走 `POST /api/images` → 后端 `image-generation.ts` [backend/src/services/image-generation.ts:202-213](backend/src/services/image-generation.ts#L202) 走 `normalizeReferenceImages()` → `readImageAsCompressedDataUrl()` ([backend/src/utils/storage.ts:103-128](backend/src/utils/storage.ts#L103)) 用 `sharp` 把 `static/xxx.png` 读出 → 旋转 → 缩放 → alpha flatten → JPEG 编码 → base64。**鸿蒙端用 `http.createHttp` 直连 Agnes，绕过了这套转换**。

## 设计目标

让鸿蒙端 i2i 流程发出去的 `extra_body.image[]` 元素**永远是合法 base64 data URI 或合法 http(s) URL**，不允许原始文件路径漏过去。

## 转换语义（与后端对齐）

参考后端 [`readImageAsCompressedDataUrl`](backend/src/utils/storage.ts#L103) 行为，对每条参考图入参做以下处理：

### 输入 → 输出

| 输入 | 检测方式 | 输出 | 失败时 |
|---|---|---|---|
| `data:image/...;base64,...` | `value.startsWith('data:')` | 透传 | — |
| `http://...` | `value.startsWith('http://')` | 透传（Agnes 支持 URL） | — |
| `https://...` | `value.startsWith('https://')` | 透传 | — |
| 绝对文件路径（默认分支） | 其他都视为本地路径 | 见下方"本地路径转换" | `hilog.warn` + 跳过该图 |

### 本地路径转换（最终方案）

1. `fileIo.statSync(path)` 检查存在 + 非空
2. `fileIo.openSync(path, READ_ONLY)` 读 buffer
3. `image.createImageSource(buffer).createPixelMap()` 解码——**单次完成**：
   - `desiredSize: { width: 768, height: 768 }`
   - `fit: 'INSIDE'` — 等比缩放保持比例
   - `ignoreAlpha: true` — 等价后端 `flatten({ background: '#ffffff' })`（已知限制：alpha flatten 后默认填黑，角色立绘通常无大面积透明，可接受）
   - **EXIF 旋转自动应用**（Harmony `ImageSource` 内置等价后端 `.rotate()`）
   - **不放大**：Harmony `fit: 'INSIDE'` 保证源图 ≤ 768×768 时不放大（保留原图尺寸），> 768×768 时等比缩到能放进 768×768 框
4. `imagePacker.packing(pixelMap, { format: 'image/jpeg', quality: 68 })` 拿到 JPEG ArrayBuffer
5. `util.Base64Helper.encodeToStr(jpegBuffer)` 拿到 base64 字符串
6. 返回 `` `data:image/jpeg;base64,${base64}` ``

> **不做手工 `if/else` 分支判断源图尺寸**：Harmony `createPixelMap` + `fit: 'INSIDE'` 的语义已经覆盖 withoutEnlargement 场景。手动分支会引入额外代码、更多状态、更多失败点，没有收益。

## 失败处理语义

| 场景 | 行为 |
|---|---|
| 路径不存在 / stat 抛错 | `hilog.warn` + `return null` |
| 文件存在但 0 字节 | `hilog.warn` + `return null` |
| `openSync` / `readSync` 抛错 | `hilog.warn` + `return null` |
| `createImageSource` 失败（非合法图像） | `hilog.warn` + `return null` |
| `createPixelMap` 失败 | `hilog.warn` + `return null` |
| `imagePacker.packing` 失败 | `hilog.warn` + `return null` |
| `Base64Helper.encodeToStr` 失败 | `hilog.warn` + `return null` |
| **任一参考图返回 null** | 该图不参与本次 i2i，其他图继续 |
| **所有参考图都返回 null** | `extra_body.image` 整个不设，走纯文生图（不报错，不 toast） |

**不抛错，不阻断整次生成，不 toast 用户**——这与后端 `normalizeReferenceImages` 的语义完全一致。

## 日志规范

每张参考图的处理结果通过 hilog 记录（INFO 成功 / WARN 失败）：

```ts
// 成功：
hilog.info(DOMAIN, TAG, 'reference resolved | path=%{public}s sizeKB=%{public}d',
  path, Math.round(base64.length * 3 / 4 / 1024));

// 失败：
hilog.warn(DOMAIN, TAG, 'reference resolve failed | path=%{public}s stage=%{public}s error=%{public}s',
  value, 'openSync' /* 或 createPixelMap/packing 等 */, err.message);

// 全部失败回退：
hilog.warn(DOMAIN, TAG, 'all %{public}d reference images failed to resolve, fall back to text-to-image', count);
```

DOMAIN 和 TAG 与 `AgnesImageRepository` 保持一致（DOMAIN = 0x0001, TAG = 'AgnesImageRepository'），方便在 hilog 里 grep。

## 改动范围

| 文件 | 行为 | 行数估计 |
|---|---|---|
| **新建** `ZdramaHarmony/entry/src/main/ets/remote/ImageReferenceResolver.ets` | 导出 `resolveImageReference(value: string): Promise<string \| null>` | +60 |
| **改** `ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets` | +1 import + 替换 if 块（5 行 → 12 行） | +13 |
| **不改** `ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets` | `buildCharacterReferences` 继续传 `imageLocalPath` | 0 |
| **不改** Vue 前端 / 后端 | 路径不通，无需触及 | 0 |

## 全局约束 (Global Constraints)

| 项 | 值 | 出处 |
|---|---|---|
| 压缩尺寸上限 | 768×768 | 后端 `image-generation.ts:206-209` |
| JPEG quality | 68 | 同上 |
| fit 模式 | `INSIDE`（保持比例，不放大） | 等价于后端 `fit: 'inside', withoutEnlargement: true` |
| 输出格式 | `image/jpeg` | 后端强制 JPEG |
| EXIF 旋转 | `createPixelMap` 默认 | 等价后端 `.rotate()` |
| Alpha flatten | `ignoreAlpha: true` | 等价后端 `flatten({ background: '#ffffff' })` |
| 失败处理 | 逐图 skip + `hilog.warn`，不阻断整次 | 后端 `normalizeReferenceImages:212` |
| 全部失败回退 | `extra_body.image` 不设，走纯文生图 | 与后端一致 |
| 透传规则 | data URI / http(s) URL 不动 | 与后端一致 |
| 命名 | 路径/函数名 camelCase；DOMAIN 0x0001；TAG 'AgnesImageRepository' | 项目现有风格 |
| 不在范围 | 不动后端、不动 Vue、不动 `buildCharacterReferences` 的 3 张上限、不重写 i2i 调用结构 | — |

## 验证方式

### 编译层

```bash
cd ZdramaHarmony
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap
```

预期：`BUILD SUCCESSFUL`，无 ArkTS 编译错误。

### 数据层

无需 DB 变更（不改 schema）。

### 端到端（必须真机）

1. **基线测试** — 项目有完整角色立绘，点"生成图片"
   - hilog 应看到：1~3 条 `reference resolved | path=...` INFO
   - API response code = 200
   - 分镜图正常生成，DB 中 `image_status = completed`
2. **全失败回退测试** — 在 dev 模式手动把 `ch.imageLocalPath` 改成不存在的路径（用 SQL 或临时改），再点"生成图片"
   - hilog 应看到：1~3 条 `reference resolve failed | stage=statSync` WARN
   - 末尾 1 条 `all N reference images failed to resolve, fall back to text-to-image` WARN
   - API response code = 200（仍能生成，只是 i2i 退化）
3. **部分失败测试** — 2 个角色，删掉 1 个本地文件，点"生成图片"
   - hilog 应看到：1 条 `reference resolved` INFO + 1 条 `reference resolve failed` WARN
   - API response code = 200，分镜图能生成
4. **边界测试** — `referenceImages` 全是 data URI / http URL
   - 应直接透传，不读文件
5. **没改前端** — `git status frontend/ app/` 应无 diff

### 真机 hilog 抓取

```bash
hdc list targets                                    # 确认设备连接
hdc shell hilog -t 2000 2>&1 | grep -E "AgnesImageRepository|image generation|reference" | tail -30
```

## 不在范围 / 风险

1. **鸿蒙 `imagePacker` 没有 mozjpeg 选项** — 后端用 `mozjpeg: true` 进一步压小 JPEG，鸿蒙没有等价能力。结果：body 会比后端稍大（~10-20%）。可接受。
2. **Harmony `image.ImageSource` 解码 PNG 大文件（>2MB）会吃较多内存** — 768×768 限制后可以接受。
3. **PNG 透明背景**：PNG→JPEG 后透明区域会变黑（因为 `ignoreAlpha: true` 等价 flatten 但默认填充黑色而非白色）。后端用 `flatten({ background: '#ffffff' })` 显式填白。**鸿蒙等价实现**：Harmony `createPixelMap` 的 `ignoreAlpha: true` 不接受 fillColor 参数。需要在编码前给 PixelMap 手动填充白底——**或者接受黑色背景**（角色立绘通常没有大面积透明，影响有限）。
   - **决策**：先接受"透明区域变黑"简化版本，spec 里标注已知限制。如果用户反馈明显，再迭代加白底填充。
4. **`util.Base64Helper` API 兼容性** — Harmony NEXT 必须确认 `util.Base64Helper.encodeToStr` 可用。如果不可用，回退到 `util.TextDecoder` + 手写 base64 编码（最后手段）。
5. **不在范围**：不改 `buildCharacterReferences` 的 3 张上限；不改角色图本身生成的逻辑（走 `AgnesImageRepository.generateImage(settings, prompt)` 无 referenceImages，不受影响）。

## Harmony 平台差异（实现期间确认的 SDK 行为）

> **本节为 spec 的"实际参数"节**，区别于前面"设计目标"里写的"理论参数"——下面记录的是 Harmony NEXT ArkTS 实际可用的 API 与真实行为，所有 spec 偏离都以本节为权威解释。

| spec 设计参数 | Harmony 实际可用 | 实际行为 | 影响 |
|---|---|---|---|
| `fit: 'INSIDE'`（等价后端 `fit: 'inside', withoutEnlargement: true`） | **不支持**——`image.DecodingOptions` 无 `fit` 字段 | 仅传 `desiredSize: { width: 768, height: 768 }`，依赖 SDK 默认 fit 行为（高度近似 INSIDE） | 真机回归时专项验证 768×768 缩放：小图不放大 / 大图保持比例 |
| `ignoreAlpha: true`（等价后端 `flatten({ background: '#ffffff' })`） | **不支持**——`image.DecodingOptions` 无 `ignoreAlpha` 字段 | 依赖 JPEG 编码天然丢 alpha（PNG 透明区域在 JPEG 编码时变黑，非白底） | 与后端"白底"偏离；角色立绘通常无大面积透明，影响有限；未来若要白底，需在 `packing` 前用 `pixelMap` operations 填白 |
| EXIF 旋转 | `createPixelMap` 默认应用 | 依赖 SDK 默认行为，无需显式 `rotate()` | 不可配置，但默认行为已满足"竖屏手机拍摄不横置"需求 |
| `fileIo.readSync(fd, size)`（返回 ArrayBuffer 直读） | **签名不同**——`(fd, length) => number` 返回已读字节数 | 必须预分配 `new ArrayBuffer(stat.size)` 再用 `(fd, buffer, { offset, length })` 重载 | 短读风险：readSync 可能返回小于 stat.size 的字节数；当前实现未校验返回的 `bytesRead`，依赖 stat.size 准确（小概率理论 bug） |
| `Base64Helper.encodeToStr(jpegBuffer)` | **方法名错**——`util.Base64Helper` 提供的是 `encodeToStringSync(src: Uint8Array): string` | 输入参数是 `Uint8Array`（不是 ArrayBuffer） | 实现层已适配：`new Uint8Array(jpegBuffer)` 再调 `encodeToStringSync` |
| `image.createImagePacker().packing(...)` | 可用 | callback 风格，包装成 Promise | ImagePacker 实例未显式 `release()`，依赖 GC（Minor resource 泄漏；详见 final-review.md M-1） |

### 实际最终参数

```ts
// 实际可用的 DecodingOptions
const pixelMap = await imageSource.createPixelMap({
  desiredSize: { width: MAX_WIDTH, height: MAX_HEIGHT },
  // fit: 'INSIDE'  ← 删除，SDK 不支持
  // ignoreAlpha: true  ← 删除，SDK 不支持
});

// 实际可用的 imagePacker
image.createImagePacker().packing(pixelMap, {
  format: 'image/jpeg',
  quality: JPEG_QUALITY,
}, (err, data) => { ... });
```

## 关联文件参考

| 角色 | 路径 |
|---|---|
| 现状调用点 | [ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets:87-89](ZdramaHarmony/entry/src/main/ets/remote/AgnesImageRepository.ets#L87) |
| 现状调用点 | [ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:380, 393-395](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L380) |
| 现状调用点 | [ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets:803-878](ZdramaHarmony/entry/src/main/ets/usecase/UseCases.ets#L803) (`buildCharacterReferences`) |
| 本地路径格式来源 | [ZdramaHarmony/entry/src/main/ets/data/MediaDownloadRepository.ets:60-63](ZdramaHarmony/entry/src/main/ets/data/MediaDownloadRepository.ets#L60) |
| 后端参考实现 | [backend/src/utils/storage.ts:103-128](backend/src/utils/storage.ts#L103) (`readImageAsCompressedDataUrl`) |
| 后端调用站点 | [backend/src/services/image-generation.ts:202-213](backend/src/services/image-generation.ts#L202) (`normalizeReferenceImages`) |
| 失败处理参考 | [backend/src/services/image-generation.ts:209-213](backend/src/services/image-generation.ts#L209) (`hilog.warn + return null`) |
