import Combine
import Foundation
import GRDB
import ZdramaCore

/// 应用级依赖容器：集中持有数据库、设置、远程仓库、用例与生成协调器。
@MainActor
final class AppContainer: ObservableObject {
    let database: DatabaseQueue
    let mediaPaths: GeneratedMediaPaths
    let settingsStore: AgnesSettingsStore
    let repository: DramaRepository

    let textRepository: AgnesTextRepository
    let imageRepository: AgnesImageRepository
    let videoRepository: AgnesVideoRepository
    let storyboardRepository: AgnesStoryboardRepository
    let downloadRepository: MediaDownloadRepository

    let coordinator: GenerationCoordinator

    private let createDramaUseCase: CreateDramaUseCase

    private init(
        database: DatabaseQueue,
        mediaPaths: GeneratedMediaPaths,
        settingsStore: AgnesSettingsStore,
        repository: DramaRepository,
        textRepository: AgnesTextRepository,
        imageRepository: AgnesImageRepository,
        videoRepository: AgnesVideoRepository,
        storyboardRepository: AgnesStoryboardRepository,
        downloadRepository: MediaDownloadRepository,
        createDramaUseCase: CreateDramaUseCase,
        coordinator: GenerationCoordinator
    ) {
        self.database = database
        self.mediaPaths = mediaPaths
        self.settingsStore = settingsStore
        self.repository = repository
        self.textRepository = textRepository
        self.imageRepository = imageRepository
        self.videoRepository = videoRepository
        self.storyboardRepository = storyboardRepository
        self.downloadRepository = downloadRepository
        self.createDramaUseCase = createDramaUseCase
        self.coordinator = coordinator
    }

    /// 打开数据库、构建全部依赖，并把启动前遗留的“生成中”项目标记为失败。
    static func bootstrap() -> AppContainer {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("Zdrama", isDirectory: true)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        guard let database = try? DramaDatabase.open(at: appDir.appendingPathComponent("zdrama.db")) else {
            fatalError("无法打开数据库：\(appDir.appendingPathComponent("zdrama.db").path)")
        }
        let mediaRoot = appDir.appendingPathComponent("media", isDirectory: true)
        let mediaPaths = GeneratedMediaPaths(root: mediaRoot)
        let settingsStore = AgnesSettingsStore(defaults: .standard, keychain: SystemKeychainStore())
        let client = URLSessionAgnesHTTPClient(timeoutSeconds: settingsStore.load().requestTimeoutSeconds)
        let repository = DramaRepository(db: database, filesRoot: mediaRoot)

        let textRepository = AgnesTextRepository(client: client)
        let imageRepository = AgnesImageRepository(client: client)
        let videoRepository = AgnesVideoRepository(client: client)
        let storyboardRepository = AgnesStoryboardRepository(client: client)
        let downloadRepository = MediaDownloadRepository(client: client, paths: mediaPaths)

        let coordinator = GenerationCoordinator(
            settingsStore: settingsStore,
            repository: repository,
            scriptUseCase: GenerateProjectScriptUseCase(repository: repository, textRepository: textRepository),
            rewriteUseCase: RewriteEpisodeScriptUseCase(repository: repository, textRepository: textRepository),
            storyboardUseCase: GenerateStoryboardsUseCase(repository: repository, storyboardRepository: storyboardRepository),
            imageUseCase: GenerateStoryboardImagesUseCase(
                repository: repository,
                imageRepository: imageRepository,
                downloadRepository: downloadRepository
            ),
            videoUseCase: GenerateStoryboardVideosUseCase(
                repository: repository,
                videoRepository: videoRepository,
                downloadRepository: downloadRepository
            ),
            composeUseCase: ComposeFinalVideoUseCase(
                dramaRepository: repository,
                composer: LocalMp4Composer(),
                paths: mediaPaths
            )
        )

        let container = AppContainer(
            database: database,
            mediaPaths: mediaPaths,
            settingsStore: settingsStore,
            repository: repository,
            textRepository: textRepository,
            imageRepository: imageRepository,
            videoRepository: videoRepository,
            storyboardRepository: storyboardRepository,
            downloadRepository: downloadRepository,
            createDramaUseCase: CreateDramaUseCase(repository: repository),
            coordinator: coordinator
        )

        // 启动时把上次退出遗留的“生成中”项目标记为失败（应用被关闭）。
        _ = try? repository.failProcessingProjects(message: "生成任务中断（应用被关闭），请重新开始")
        return container
    }

    // MARK: - 便捷方法

    func loadProjects() throws -> [DramaProject] {
        try repository.getProjects()
    }

    @discardableResult
    func createDrama(
        title: String,
        prompt: String,
        style: String,
        audience: String,
        aspect: String,
        shotCount: Int,
        duration: Int
    ) throws -> Int64 {
        try createDramaUseCase.execute(
            CreateDramaInput(
                title: title,
                prompt: prompt,
                style: style,
                targetAudience: audience,
                aspectRatio: aspect,
                shotCount: shotCount,
                shotDurationSeconds: duration
            )
        )
    }

    /// 先取消该项目的进行中任务，再删除项目记录与媒体文件。
    @discardableResult
    func deleteProject(_ projectId: Int64) async throws -> Bool {
        if let episode = try? repository.getEpisodeForProject(projectId) {
            await coordinator.cancel(projectId: projectId, episodeId: episode.id)
        }
        let deleted = try repository.deleteProject(projectId)
        try? downloadRepository.deleteGeneratedMedia(projectId: projectId)
        return deleted
    }
}
