# iOS 角色提取、角色图与角色列表

> 只补 Swift 版 `ZdramaIOS/`（火宝短剧）。行为对齐 Android：`ExtractCharactersUseCase`、`GenerateCharacterImagesUseCase`、`GenerateSingleCharacterImageUseCase`。Objective-C 版不在本次范围。

## 意图

剧本写完后，用户要能从当前集抽出角色、给角色画立绘，并在一页里查看。iOS 已有 `characters` 表、`Character` 模型和角色提取提示词常量，但没有读写、没有调用、详情页也没有入口。

## 目标

- 项目详情可「提取角色」「生成角色图」「查看角色」。
- 同名角色更新文案并保留已有立绘；新角色插入；本次未出现的旧角色不删除。
- 批量出图跳过已完成且本地文件还在的立绘；列表里单张重画直接覆盖。
- 提示词页增加「角色提取」标签，可编辑、保存、恢复默认。
- 提取和出图进入现有生成队列，进行中禁用生成按钮，可取消。

## 非目标

- 不改 Objective-C 工程。
- 不把角色参考图注入分镜出图。
- 不在「全部生成」里自动提取角色或出角色图。
- 不做角色编辑、删除单个角色、删除单张立绘。
- 不按集拆角色列表。角色挂在项目上，和 Android 一致。

## 数据

`CharacterLocalDataSource` 增加：

- `getCharacters(projectId:)`：按 `id` 升序。
- `upsertCharacters(projectId:characters:)`：`id > 0` 只更新 `role`、`description`、`appearance`、`personality`、`updated_at`；`id == 0` 插入新行。不删除未提及角色。
- `updateCharacterImage(characterId:status:url:localPath:errorMessage:)`：更新立绘四字段和 `updated_at`。

`DramaRepository` 暴露同名方法。删除项目时继续调用现有的 `deleteCharactersForProject`。

角色图文件：`generated/<projectId>/char_<characterId>_image.<ext>`，扩展名沿用现有下载逻辑。

## 提取

`ExtractCharactersUseCase.execute(projectId:episodeId:settings:)`：

- 项目或剧集不存在，抛对应的 not found。
- 当前集 `scriptContent` 为空白：`请先为本集创作或改写脚本`。不回退项目级剧本。
- 系统提示词用 `PromptResolver.resolve(custom: settings.customCharacterExtractPrompt, default: PromptDefaults.characterExtractPrompt)`。
- 用户提示词与 Android 相同：要求 JSON 数组，字段 `name`、`role`、`description`、`appearance`、`personality`；已有角色时追加同名合并说明，并要求带 `existing_id`。已有名字列表用 `、` 连接。
- 温度 `0.3`，`maxTokens` `4000`。响应用现有的 chat 文本提取，再截取第一个 `[` 到最后一个 `]`。
- 无法解析、空数组、或没有非空 `name`：分别是 `无法解析角色提取结果`、`未从剧本中提取到角色`。
- 同名匹配已有角色时沿用其 `id`、立绘状态、URL、本地路径和错误信息；空白字段保留旧值。`role` 空白时保留旧 `role`。
- 返回写入条数。

## 出图

提示词：`"<name>, <appearance 或 description 或 character portrait>, high quality, front-facing portrait"`。请求复用 `AgnesImageRepository.generateImage`（1024x768）。

批量 `GenerateCharacterImagesUseCase`：

- 无角色：`请先提取角色`。
- `forceRegenerate == false` 且状态为 `COMPLETED`、本地文件存在：跳过。
- 否则标 `PROCESSING`，成功下载后标 `COMPLETED` 并写入路径；失败标 `FAILED` 并写入错误，继续下一个。
- 全部成功或至少一张新图成功时返回新生成数量；一张都没生成且有失败时抛出第一个错误。

单张 `GenerateSingleCharacterImageUseCase` 默认 `forceRegenerate = true`，失败即抛出，不继续。

## 队列

`GenerationStageKey` 增加 `characterExtract = "character_extract"`、`characterImage = "character_image"`。

- 提取的任务键与现有阶段相同：`generation-<projectId>-<episodeId>-character_extract`。取消当前集时一起取消。
- 批量角色图是项目级的，任务键为 `generation-<projectId>-character_image`，不含剧集 id。角色挂在项目上，两集不能同时画同一批立绘。详情页的取消会取消这个项目级任务。
- 详情确认「覆盖」后，`forceRegenerate = true` 必须传进用例，不能只用来替换队列槽。现有 `enqueue` 把这个标志用完就丢掉了；本次只对 `character_image` 传到用例。为 true 时已完成的立绘也重画。
- 详情页用 `isRunning(projectId:episodeId:)` 判断按钮是否禁用。这个判断今天只看同一集的任务。项目级角色图任务没有剧集 id，也必须让同一项目的详情页视为进行中，否则生成按钮在出图时不会禁用。
- 单张重画的任务键是 `character_image_<characterId>`，默认强制重画，不和批量任务互相覆盖。

详情页：

- 「提取角色」在没有剧本时直接提示，不入队。已有角色时确认框文案用 Android 的：`当前项目已有角色信息，重新提取会覆盖现有角色。是否继续？` 按钮为覆盖和取消。确认后入队。
- 「生成角色图」在没有角色时提示 `请先提取角色`。已有完成立绘时确认：`当前项目已有角色图，重新生成会覆盖所有角色图。是否继续？` 确认后 `forceRegenerate = true`，否则 `false`。
- 「查看角色」始终可进。列表为空时显示 `该项目暂无角色，请先在项目详情页提取角色`。

## 查看页

导航标题 `项目角色`。每张卡片：本地立绘（没有则显示状态）、名字、`role`（空则 `角色定位未填`）、描述、外貌、性格、失败原因。卡片上的「生成图片」入队单张重画。页面在出现时重新读取。

## 提示词

`ManagePromptsView` 增加 `角色提取` 标签，绑定 `customCharacterExtractPrompt`，默认文案 `PromptDefaults.characterExtractPrompt`。保存、恢复默认、未保存离开确认与现有三个标签一致。

## 测试

- 仓库：插入后能读出；同名 upsert 保留 id 和立绘；未提及角色仍在。
- 提取：空白剧本失败且不请求；同名合并保留立绘；新名字插入；响应包在说明文字里的 JSON 数组仍能解析。
- 出图：已完成且文件存在的角色被跳过；失败角色标 `FAILED`，后面的角色继续；单张强制重画。
- 协调器：`character_extract` 会调用提取用例。

## 构建者自行决定

- 角色图下载方法加在现有 `MediaDownloadRepository`，不新建仓库。
- 单张重画复用协调器，阶段键为 `character_image_<characterId>`，`forceRegenerate` 固定为 true。批量角色图的键不含剧集 id，见「队列」。
- 详情按钮放在内容查看区，「查看剧本」之后，文案与 Android 字符串一致。
