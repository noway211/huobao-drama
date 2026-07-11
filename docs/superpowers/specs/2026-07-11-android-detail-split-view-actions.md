# Android 详情页拆分:每阶段一排「生成 + 查看」

**日期**：2026-07-11
**范围**：`ZdramaAndroid/` (Android 端)

## 背景

`ProjectDetailActivity` 承担了过多职责,阅读和使用成本都偏高:

- 一屏纵向堆了 10 个 match_parent 的按钮(一键生成、取消、脚本、分镜、图片、视频、成片、播成片、播视频、删除),用户滚动才能看全
- 详情页底部直接展示大段 `scriptText` 和 `storyboardText` 纯文本,是把中间产物直接倾倒在详情页里
- 已经生成的图片只能读一个 URL 字符串,无法预览

## 目标

- 详情页只保留标题、状态、meta 和按钮组,变轻
- 除「一键生成短剧」「合成成片 MP4」「播放成片」「删除项目」保持整行外,4 个阶段(脚本 / 分镜 / 图片 / 视频)改为同一行「生成 X」+「查看 X」两个等宽按钮
- 「查看」按钮统一新开独立 Activity 展示对应内容,详情页不再承载正文
- 图片阶段的「查看」提供缩略图列表,而不是文本 URL

## 非目标

- 不改动生成流程本身、`GenerationWorker` 逻辑或后台任务链
- 不添加图片加载库(Glide/Coil 等),用 `BitmapFactory` + `inSampleSize` 采样
- 不做点图放大 / 单图重生成入口 — 那属于后续独立功能
- 不改动 `VideoPlayerActivity`,只是被详情页里的「播放视频」按钮沿用

## 页面结构

详情页 (`ActivityProjectDetail`) 自上而下:

1. 标题 / 状态 / 后台生成状态
2. `promptText` + `metaText`
3. 一整行:【一键生成短剧】
4. 一整行:【取消生成】(仅进行中可见)
5. 两列一行 × 4:
   - `[生成脚本]      [查看脚本]`
   - `[生成分镜]      [查看分镜]`
   - `[生成图片]      [查看图片]`
   - `[生成视频]      [播放视频]` — 沿用现有 `VideoPlayerActivity`
6. 一整行:【合成成片 MP4】
7. 一整行:【播放成片】
8. 一整行:【删除项目】

原详情页里的 `scriptTitleText / scriptText / storyboardTitleText / storyboardText` 从 layout 中删除。

## 新增 Activity

### `ScriptViewerActivity`

- 布局:标题 + 项目名 + `ScrollView` 里一个可选择的 `TextView`
- 传入 `EXTRA_PROJECT_ID`;通过 `GetProjectDetailUseCase` 加载 `project.generatedScript`
- 脚本为空或项目不存在:Toast 提示后 `finish()`

### `StoryboardViewerActivity`

- 布局:标题 + 项目名 + `ScrollView` 里一个可选择的 `TextView`
- 通过 `GetStoryboardsUseCase` 加载,展示格式与旧详情页完全一致
- 分镜为空或项目不存在:Toast 提示后 `finish()`

### `ImageGalleryActivity` + `ImageGalleryAdapter`

- `RecyclerView` 线性列表,单列
- Item:`ImageView`(match_parent × 220dp)+ `#{shotNumber} 场景` + 图片状态
- 加载策略(三挡回退):
  1. `imageLocalPath` 指向的本地文件存在:用 `BitmapFactory.decodeFile` 探测尺寸 → `inSampleSize` 采样(目标最大边 1024)→ 解码
  2. 没有本地文件但有 `imageUrl`:仅显示 URL + 「图片在远端」提示
  3. 两者都没有:显示「图片尚未生成 (状态)」占位
- 分镜为空或全部无图:Toast 提示后 `finish()`

## 公共格式化工具

抽出 `StoryboardTextFormatter.format(context, storyboards)`,承接原 `ProjectDetailActivity.formatStoryboards`,详情页与 `StoryboardViewerActivity` 共享同一格式。原 `formatStoryboards` 移除。

## `ProjectDetailActivity` 改动

- 新增 3 个点击监听:`viewScriptButton` / `viewStoryboardButton` / `viewImagesButton` 分别 `startActivity(...)`
- `bindProject` 里三个查看按钮的 `isEnabled` 根据数据决定:
  - `viewScriptButton.isEnabled = !project.generatedScript.isNullOrBlank()`
  - `viewStoryboardButton.isEnabled = storyboards.isNotEmpty()`
  - `viewImagesButton.isEnabled = storyboards.any { isExistingFile(it.imageLocalPath) || !it.imageUrl.isNullOrBlank() }`
- 删除 `bindProject` 里对 `scriptText / storyboardText` 的赋值(以及对应 title)
- 保留全部生成流逻辑:`bindGenerationButtonTexts / confirmGeneration / regenerationWarningMessageRes / cancelGeneration / observeGenerationWork` 等一律不动

## 布局改动

`activity_project_detail.xml` 每个「两列一行」采用 `LinearLayout horizontal + weight=1` 模式,例如脚本行:

```xml
<LinearLayout
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginTop="12dp"
    android:orientation="horizontal">
    <Button
        android:id="@+id/generateScriptButton"
        android:layout_width="0dp" android:layout_height="wrap_content"
        android:layout_marginEnd="8dp" android:layout_weight="1"
        android:text="@string/project_generate_script" />
    <Button
        android:id="@+id/viewScriptButton"
        android:layout_width="0dp" android:layout_height="wrap_content"
        android:layout_marginStart="8dp" android:layout_weight="1"
        android:text="@string/project_view_script" />
</LinearLayout>
```

分镜、图片、视频行沿用同样结构。视频行第二列复用旧的 `playVideosButton`。

## 新增字符串(`res/values/strings.xml`)

```
project_view_script              查看脚本
project_view_storyboard          查看分镜
project_view_images              查看图片
project_no_script                暂无脚本
project_no_storyboards           暂无分镜
project_no_images                暂无生成图片
project_script_title             脚本正文
project_storyboard_title         分镜列表
project_image_gallery_title      图片列表
project_image_placeholder_pending 图片尚未生成
project_image_placeholder_remote 图片在远端（无本地文件）
```

## 涉及文件

**修改**

- `ZdramaAndroid/app/src/main/res/layout/activity_project_detail.xml`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/ProjectDetailActivity.kt`
- `ZdramaAndroid/app/src/main/res/values/strings.xml`
- `ZdramaAndroid/app/src/main/AndroidManifest.xml`

**新增**

- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/StoryboardTextFormatter.kt`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/ScriptViewerActivity.kt` + `res/layout/activity_script_viewer.xml`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/StoryboardViewerActivity.kt` + `res/layout/activity_storyboard_viewer.xml`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/ImageGalleryActivity.kt` + `res/layout/activity_image_gallery.xml`
- `ZdramaAndroid/app/src/main/java/com/huobao/zdrama/ui/project/ImageGalleryAdapter.kt` + `res/layout/item_image_gallery.xml`

## 验证

1. `./gradlew assembleDebug` — BUILD SUCCESSFUL,仅保留原有 3 个非阻塞警告(`MasterKeys` 弃用、未用参数)
2. `adb install -r` 覆盖安装到 `3040004917007Q3` — Success
3. 详情页:
   - 4 组「生成 X + 查看 X」按钮左右并排,占满一行
   - 底部原大段脚本文本 / 分镜文本已消失
   - 「一键生成」「合成成片 MP4」「播放成片」「删除项目」仍为整行
4. 「查看脚本 / 查看分镜 / 查看图片」分别打开独立页;项目未生成对应内容时 Toast 提示并 finish
5. 图片列表:已生成分镜显示缩略图 + 编号 + 场景;未生成分镜显示占位
6. 「播放视频」按钮沿用旧行为,能打开 `VideoPlayerActivity`
