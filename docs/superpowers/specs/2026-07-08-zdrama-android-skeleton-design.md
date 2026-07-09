# ZdramaAndroid 可编译骨架设计

## Context

用户希望在当前仓库下的 `ZdramaAndroid/` 目录新增一个独立 Android 工程，参考 `2026-07-07-android-agnes-mobile-drama-design.md` 的 Android 端 Agnes 短剧生成方向，但本阶段只完成可编译工程骨架。

本阶段固定使用：

- Android Gradle Plugin: `4.2.2`
- Gradle Wrapper: `6.8.3`
- UI: Android XML + ViewBinding，不使用 Jetpack Compose
- 工程目录：`ZdramaAndroid/`

## Goal

建立一个能被 Android Studio/Gradle 识别并构建的 Android App 工程骨架，为后续 Agnes 短剧生成 MVP 做准备。

本阶段成功标准：

- `ZdramaAndroid/` 下存在独立 Gradle Android 工程。
- Gradle/AGP/Kotlin/AndroidX 版本组合与 AGP 4.2.2 兼容。
- App module 能开启 ViewBinding。
- 存在基础 Activity、XML 页面、Manifest、资源和包结构。
- 后续 MVP 所需的 Room、Retrofit/OkHttp、WorkManager、Media2、Material Components 依赖先进入工程配置。
- 放置最小 Kotlin 骨架类，表达 Android 方案中的主要边界，但不实现完整生成流程。

## Non-Goals

本阶段不做：

- 不完整打通 Agnes 文本、图片、视频生成流程。
- 不实现真实 API Key 加密存储和设置页业务逻辑。
- 不实现 Room 完整 schema 和迁移。
- 不实现 WorkManager 长任务 pipeline。
- 不实现 Media2 连续播放功能。
- 不做 FFmpeg 合成、字幕烧录、TTS、音色、试听或配音。
- 不引入 Jetpack Compose。
- 不运行现有 Node 后端，也不依赖当前 frontend/backend 工程启动。

## Build Design

`ZdramaAndroid/` 作为独立 Gradle 工程，包含：

- `settings.gradle`
- 根 `build.gradle`
- `gradle.properties`
- `gradlew`、`gradlew.bat`
- `gradle/wrapper/gradle-wrapper.properties`
- `app/build.gradle`

版本选择：

- `com.android.tools.build:gradle:4.2.2`
- Gradle distribution: `gradle-6.8.3-all.zip`
- Kotlin Gradle plugin: `1.5.31`
- `compileSdkVersion 33`
- `minSdkVersion 23`
- `targetSdkVersion 33`

这些版本偏保守，目的是优先保证 AGP 4.2.2 环境可同步和构建。后续如果需要更高 Android SDK 或新版库，应单独升级构建基线。

## Dependency Design

App module 使用 Kotlin Android 插件并开启 ViewBinding。本阶段不启用 KAPT；Room compiler 留到后续 MVP 阶段在构建基线允许时接入。

基础依赖包括：

- AndroidX AppCompat
- AndroidX Core KTX
- ConstraintLayout
- Material Components
- Lifecycle ViewModel / LiveData 或 StateFlow 兼容依赖
- Room runtime（本阶段不启用 Room compiler/KAPT，避免 AGP 4.2.2 + Kotlin 1.5.31 在 Mac arm64 上触发旧 Room compiler native sqlite 兼容问题）
- Retrofit
- OkHttp logging interceptor
- Gson
- WorkManager KTX
- AndroidX Media2 Player/Widget

依赖版本要避免要求 AGP 7+ 或 Java 17。若某个新版库与 AGP 4.2.2 不兼容，优先降级该库，而不是升级 AGP。

## Android App Skeleton

包名建议：`com.huobao.zdrama`

首屏只做骨架 UI：

- App 标题：`ZDrama Android`
- 当前阶段说明：Android Agnes drama skeleton
- 三个占位入口：Settings、Create、Projects

首屏用于验证 XML、ViewBinding、Material/AppCompat 主题和 Activity 启动链路。占位入口可以先不跳转，或跳转到简单 placeholder Activity/Fragment；本阶段优先保持代码少而可编译。

## Package Boundaries

按原 Android 方案保留后续 MVP 的分层边界：

- `data.local`: Room database、entities、DAO
- `data.remote`: Retrofit services、OkHttp interceptors、Agnes DTO
- `data.repository`: DramaRepository、GenerationRepository、SkillRepository
- `domain.model`: App 内部业务模型
- `domain.usecase`: CreateDramaUseCase、GenerateImagesUseCase、GenerateVideosUseCase、RetryStoryboardUseCase
- `skill`: BuiltInSkillRegistry、SkillEngine、SkillInputValidator、SkillJsonParser
- `worker`: WorkManager workers
- `ui.main`: MainActivity 和首屏 UI
- `ui.settings`: 设置页占位
- `ui.create`: 创建页占位
- `ui.project`: 项目详情/进度页占位
- `ui.storyboard`: 分镜详情页占位
- `ui.player`: 播放页占位

骨架类只提供清晰边界和最小类型定义，避免在第一阶段写半成品业务逻辑。

## Data Skeleton

Room 先定义最小实体和数据库类，字段以原 Android 方案为方向，但本阶段只保证编译：

- `ProjectEntity`
- `CharacterEntity`
- `SceneEntity`
- `StoryboardEntity`
- `SkillConfigEntity`
- `DramaDatabase`

DAO 可以先提供少量基础查询签名。后续实现 MVP 时再补充完整字段约束、索引、状态枚举和事务。

## Remote Skeleton

Agnes 远端层先定义接口和 DTO 边界：

- `AgnesApiService`
- `AgnesAuthInterceptor`
- chat completion request/response DTO
- image/video generation request/response DTO 占位

本阶段不真实发起网络请求，也不保存 API Key。`AgnesAuthInterceptor` 可以保留 token provider 接口，后续接入 EncryptedSharedPreferences/Keystore。

## Worker And Skill Skeleton

WorkManager 和 skill 先保留最小入口：

- `GenerationWorker`：可编译的 Worker 占位，不执行真实 pipeline。
- `BuiltInSkillRegistry`：返回固定内置 skill 列表。
- `SkillEngine`：保留执行接口，返回 placeholder 结果。

这样后续能按文本生成、图片生成、视频生成三个阶段逐步填充，而不改变包边界。

## Gitignore Updates

仓库根 `.gitignore` 需要追加 Android/Gradle 常见忽略项：

- `.gradle/`
- `build/`
- `*/build/`
- `local.properties`
- Android Studio 生成的本地文件

不能忽略 Gradle wrapper jar，因为工程需要可复现的 Gradle 6.8.3 wrapper。

## Verification

实现后优先运行：

```bash
cd ZdramaAndroid
./gradlew assembleDebug
```

如果本机缺 Android SDK、SDK 33 未安装，或网络无法下载 Gradle/依赖，应记录实际失败信息。只要工程文件完整且失败原因是环境缺失或外部下载问题，就不把它伪装成代码已验证通过。

## Implementation Notes

- 第一阶段保持独立 Android 工程，不修改现有 backend/frontend 架构。
- 不把 Android 工程并入当前 Node package 管理。
- 不新增 Compose 依赖。
- 使用 Java 8 source/target compatibility，匹配 AGP 4.2.2 常见配置；本地构建 Gradle 6.8.3 需使用 JDK 8 或 JDK 11，不支持 JDK 17。
- 使用 AndroidX Media2 作为播放器依赖占位，不引入 Media3。
