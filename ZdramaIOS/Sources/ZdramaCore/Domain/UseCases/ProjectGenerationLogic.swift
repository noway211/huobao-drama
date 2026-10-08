import Foundation

/// 项目详情页的纯逻辑：覆盖判定、生成进度与阶段中文名。
/// 全部为无副作用函数，便于在核心包内直接测试，SwiftUI 层只做展示。
public enum ProjectGenerationLogic {
    /// 目标内容已存在时返回 true，UI 需要弹出覆盖确认（确认后以 forceRegenerate=true 入队）。
    /// - text/rewrite/full：已有非空白脚本
    /// - storyboard：已有分镜（shots 非空）
    /// - image：任一镜头图片已完成
    /// - video：任一镜头视频已完成
    /// - final_video：剧集成片状态为 completed 且存在本地成片文件
    public static func shouldConfirmOverwrite(
        stage: String,
        project: DramaProject,
        episode: Episode?,
        shots: [StoryboardShot]
    ) -> Bool {
        switch stage {
        case GenerationStageKey.text, GenerationStageKey.rewrite, GenerationStageKey.full:
            return !isBlank(episode?.scriptContent) || !isBlank(project.generatedScript)
        case GenerationStageKey.storyboard:
            return !shots.isEmpty
        case GenerationStageKey.image:
            return shots.contains { $0.imageStatus == .completed }
        case GenerationStageKey.video:
            return shots.contains { $0.videoStatus == .completed }
        case GenerationStageKey.finalVideo:
            return (episode?.finalVideoStatus ?? .pending) == .completed
                && !isBlank(episode?.finalVideoLocalPath)
        default:
            return false
        }
    }

    /// 根据当前阶段与镜头快照计算进度：IMAGE/VIDEO 阶段给出 completed/total（如“出图 3/8”），
    /// 并标注正在生成的镜头号。
    public static func progress(
        stage: GenerationStage,
        shots: [StoryboardShot]
    ) -> ProjectProgress {
        switch stage {
        case .image:
            return ProjectProgress(
                stage: stage,
                completedCount: shots.filter { $0.imageStatus == .completed }.count,
                totalCount: shots.count,
                processingShotNumber: shots.first { $0.imageStatus == .processing }?.shotNumber
            )
        case .video:
            return ProjectProgress(
                stage: stage,
                completedCount: shots.filter { $0.videoStatus == .completed }.count,
                totalCount: shots.count,
                processingShotNumber: shots.first { $0.videoStatus == .processing }?.shotNumber
            )
        default:
            return ProjectProgress(
                stage: stage,
                completedCount: 0,
                totalCount: shots.count,
                processingShotNumber: nil
            )
        }
    }
}

/// 生成进度的值对象：completed/total 与生成中的镜头号。
public struct ProjectProgress: Equatable, Sendable {
    public let stage: GenerationStage
    public let completedCount: Int
    public let totalCount: Int
    public let processingShotNumber: Int?

    public init(
        stage: GenerationStage,
        completedCount: Int,
        totalCount: Int,
        processingShotNumber: Int?
    ) {
        self.stage = stage
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.processingShotNumber = processingShotNumber
    }

    /// 进度比例（0...1），无总数目时返回 0。
    public var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    /// 进度文案：如“出图 3/8”“正在生成分镜…”。
    public var displayText: String {
        switch stage {
        case .image:
            return totalCount > 0 ? "出图 \(completedCount)/\(totalCount)" : "出图"
        case .video:
            return totalCount > 0 ? "出视频 \(completedCount)/\(totalCount)" : "出视频"
        case .text:
            return "正在生成剧本…"
        case .storyboard:
            return "正在生成分镜…"
        case .finalVideo:
            return "正在合成成片…"
        case .none:
            return "未开始"
        }
    }
}

public extension GenerationStage {
    /// 阶段中文名：剧本 / 分镜 / 出图 / 出视频 / 成片。
    var displayName: String {
        switch self {
        case .none: return "未开始"
        case .text: return "剧本"
        case .storyboard: return "分镜"
        case .image: return "出图"
        case .video: return "出视频"
        case .finalVideo: return "成片"
        }
    }
}

public extension ProjectStatus {
    /// 状态中文名：草稿 / 生成中 / 已完成 / 失败 / 已取消。
    var displayName: String {
        switch self {
        case .draft: return "草稿"
        case .processing: return "生成中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
