import Combine
import Foundation
import ZdramaCore

/// 项目详情页 ViewModel：负责加载项目/剧集/分镜、生成前的预检与覆盖确认、调用协调器。
@MainActor
final class ProjectDetailViewModel: ObservableObject {
    let projectId: Int64

    @Published private(set) var project: DramaProject?
    @Published private(set) var episode: Episode?
    @Published private(set) var shots: [StoryboardShot] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var loadError: String?
    @Published private(set) var alertMessage: String?
    @Published private(set) var pendingOverwriteStage: String?

    private let repository: DramaRepository
    private let coordinator: GenerationCoordinator
    private let settingsStore: AgnesSettingsStore

    init(
        projectId: Int64,
        repository: DramaRepository,
        coordinator: GenerationCoordinator,
        settingsStore: AgnesSettingsStore
    ) {
        self.projectId = projectId
        self.repository = repository
        self.coordinator = coordinator
        self.settingsStore = settingsStore
    }

    // MARK: - 派生状态

    /// 当前生成进度（completed/total 与生成中的镜头号）。
    var progress: ProjectProgress {
        ProjectGenerationLogic.progress(
            stage: project?.currentStage ?? .none,
            episode: episode,
            shots: shots
        )
    }

    /// 是否有可查看的剧本（非空白）。
    var hasScript: Bool {
        !isBlank(episode?.scriptContent) || !isBlank(project?.generatedScript)
    }

    /// 是否有已生成的图片（本地文件或远程地址均可）。
    var hasGallery: Bool {
        shots.contains { shot in
            if let path = shot.imageLocalPath, FileManager.default.fileExists(atPath: path) {
                return true
            }
            return !isBlank(shot.imageUrl)
        }
    }

    /// 是否有已生成的镜头视频（本地文件或远程地址均可）。
    var hasShotVideos: Bool {
        shots.contains { shot in
            if let path = shot.videoLocalPath, FileManager.default.fileExists(atPath: path) {
                return true
            }
            return !isBlank(shot.videoUrl)
        }
    }

    /// 是否有可播放的成片（completed 且本地文件存在）。
    var hasFinalVideo: Bool {
        guard let path = episode?.finalVideoLocalPath else { return false }
        return episode?.finalVideoStatus == .completed && FileManager.default.fileExists(atPath: path)
    }

    /// 标题：用于导航栏展示。
    var title: String {
        project?.title ?? "详情"
    }

    // MARK: - 加载

    /// 1.5 秒定时刷新入口：重新读取项目、剧集与分镜，并同步运行状态。
    func refresh() {
        reload()
        Task { await refreshRunningState() }
    }

    func dismissAlert() {
        alertMessage = nil
    }

    private func reload() {
        do {
            project = try repository.getProject(projectId)
            episode = try repository.getEpisodeForProject(projectId)
            if let episode {
                shots = try repository.getStoryboards(projectId: projectId, episodeId: episode.id)
            } else {
                shots = []
            }
            loadError = nil
        } catch {
            loadError = "加载失败：\(error.localizedDescription)"
        }
    }

    private func refreshRunningState() async {
        guard let episode else {
            isGenerating = false
            return
        }
        isGenerating = await coordinator.isRunning(projectId: projectId, episodeId: episode.id)
    }

    // MARK: - 分镜提示词

    /// 保存指定镜头的图片提示词，并同步本地镜头快照。
    func saveImagePrompt(shotId: Int64, prompt: String) {
        do {
            try repository.updateShotImagePrompt(shotId: shotId, newPrompt: prompt)
            if let index = shots.firstIndex(where: { $0.id == shotId }) {
                shots[index].imagePrompt = prompt
            }
        } catch {
            alertMessage = "保存图片提示词失败：\(error.localizedDescription)"
        }
    }

    /// 保存指定镜头的视频提示词，并同步本地镜头快照。
    func saveVideoPrompt(shotId: Int64, prompt: String) {
        do {
            try repository.updateShotVideoPrompt(shotId: shotId, newPrompt: prompt)
            if let index = shots.firstIndex(where: { $0.id == shotId }) {
                shots[index].videoPrompt = prompt
            }
        } catch {
            alertMessage = "保存视频提示词失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 生成

    /// 生成入口：先跑 preflight（失败直接提示，不入队），目标已存在时弹覆盖确认。
    func generate(_ stage: String) {
        guard !isGenerating, let project, let episode else { return }
        alertMessage = nil
        do {
            try GenerationPreflight.check(
                stage: stage,
                input: preflightInput(project: project, episode: episode)
            )
        } catch let error as PreflightError {
            alertMessage = Self.chineseMessage(for: error)
            return
        } catch {
            alertMessage = "生成前检查失败：\(error.localizedDescription)"
            return
        }
        if ProjectGenerationLogic.shouldConfirmOverwrite(
            stage: stage,
            project: project,
            episode: episode,
            shots: shots
        ) {
            pendingOverwriteStage = stage
        } else {
            enqueue(stage: stage, forceRegenerate: false)
        }
    }

    /// 用户确认覆盖已有结果。
    func confirmOverwrite() {
        guard let stage = pendingOverwriteStage else { return }
        pendingOverwriteStage = nil
        enqueue(stage: stage, forceRegenerate: true)
    }

    /// 用户取消覆盖确认弹窗。
    func cancelOverwrite() {
        pendingOverwriteStage = nil
    }

    /// 取消当前生成任务。
    func cancel() {
        guard let episode else { return }
        Task {
            await coordinator.cancel(projectId: projectId, episodeId: episode.id)
            refresh()
        }
    }

    private func enqueue(stage: String, forceRegenerate: Bool) {
        guard let project, let episode else { return }
        Task {
            await coordinator.enqueue(
                projectId: project.id,
                episodeId: episode.id,
                stage: stage,
                forceRegenerate: forceRegenerate
            )
            refresh()
        }
    }

    private func preflightInput(project: DramaProject, episode: Episode) -> PreflightInput {
        PreflightInput(
            apiKey: settingsStore.load().apiKey,
            episodeContent: episode.content,
            scriptContent: episode.scriptContent ?? project.generatedScript,
            shots: shots,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    /// 把 PreflightError 映射为中文提示。
    private static func chineseMessage(for error: PreflightError) -> String {
        switch error {
        case .missingApiKey:
            return "请先在「设置」中配置 Agnes API Key"
        case .missingRawContent, .missingScript:
            return "请先为本集创作或改写剧本"
        case .missingStoryboards:
            return "请先点击「剧本」或「全部生成」，完成剧本后再生成 分镜"
        case .missingImages:
            return "请先生成分镜图"
        case .missingLocalVideos:
            return "请先生成并下载全部分镜视频后再合成成片"
        }
    }
}

private func isBlank(_ value: String?) -> Bool {
    value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
}