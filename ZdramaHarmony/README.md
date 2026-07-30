# ZdramaHarmony

火豹短剧 Android 版（`ZdramaAndroid/`）的 HarmonyOS NEXT（API 12+，纯 ArkTS / Stage 模型）移植。

本次为 **MVP**：跑通「设置 → 创建项目 → 详情 → 创作/改写脚本 → 查看脚本」核心链路。图片、视频、分镜、成片拼接、API 日志页等后续阶段补齐。

## 打开方式

用 **DevEco Studio 5.0+** 打开 `ZdramaHarmony/` 目录，等待 hvigor 同步后即可运行到 HarmonyOS NEXT 模拟器 / 真机。

## 目录结构

```
ZdramaHarmony/
├── AppScope/                     # 应用级配置 + 图标
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/     # EntryAbility（Stage 模型入口，初始化 AppContext）
│       │   ├── common/           # AppContext（context 持有）、Theme（暗色主题 + 状态文案）
│       │   ├── model/            # DramaModels、AgnesSettings（对齐 Android domain/model）
│       │   ├── data/             # RDB 数据库 + 数据源 + 仓库 + 设置存储
│       │   │   ├── DramaDatabase.ets          # relationalStore，建 projects/episodes/storyboards
│       │   │   ├── ProjectLocalDataSource.ets
│       │   │   ├── EpisodeLocalDataSource.ets
│       │   │   ├── DramaRepository.ets        # 门面 + 级联删除
│       │   │   └── SettingsStore.ets          # Preferences（api key 独立 store）
│       │   ├── remote/           # HTTP 层（@ohos.net.http）
│       │   │   ├── AgnesTextRepository.ets    # chat/completions：生成 + 改写
│       │   │   ├── ChatResponseTextExtractor.ets
│       │   │   └── ApiLogStore.ets            # 内存环形缓冲 + base64 脱敏
│       │   ├── usecase/          # UseCases（create/get/generate/rewrite/delete）
│       │   └── pages/            # Index / Settings / CreateProject / ProjectDetail / ScriptViewer
│       ├── resources/
│       └── module.json5
└── build-profile.json5
```

## 与 Android 版的映射

| Android | HarmonyOS |
|---|---|
| SQLiteOpenHelper (`DramaLocalDatabase`) | `@ohos.data.relationalStore`（`DramaDatabase.ets`） |
| EncryptedSharedPreferences + SharedPreferences | `@ohos.data.preferences`（`SettingsStore.ets`，api key 独立 store） |
| Retrofit + OkHttp + 拦截器 | `@ohos.net.http`（`AgnesTextRepository.ets` 内联鉴权/日志） |
| Activity + XML + ViewBinding | ArkUI `@Entry @Component` 声明式页面 |
| RecyclerView + Adapter | `List` + `LazyForEach`/`ForEach` |
| AlertDialog | `promptAction.showDialog` |
| 长按删除项目 | `LongPressGesture` + 确认框 |

数据模型、DB schema（列名/枚举以字符串存储）、改写 system prompt 均与 Android 版**一比一对齐**，两端可读同结构数据。

## MVP 未包含（后续阶段）

- 分镜生成（storyboards 表已建好，待填）
- 图片 / 视频生成、轮询、本地下载
- 成片 MP4 拼接（Harmony 侧 AVMuxer/AVDemuxer，需同格式校验或转码兜底）
- 视频播放器、图片画廊、API 日志查看页
- 后台长时任务（Android 的 WorkManager 前台服务 → Harmony ContinuousTask）

## 已对齐 Android 的行为细节

- 创建项目默认值：风格「现代短剧」、受众「大众受众」、分镜 8、时长 5、画幅 9:16
- 设置「测试文本模型」：专用 ping（单条 `ping`、temp 0、max_tokens 8），与 Android 一致
- 冷启动清理：进程启动时把僵尸 `PROCESSING` 项目重置为 `FAILED`（对应 `ZdramaApplication`）
- 创作/改写脚本的覆盖确认框文案、脚本查看空态返回、各类 Toast 文案均与 Android 逐字对齐
