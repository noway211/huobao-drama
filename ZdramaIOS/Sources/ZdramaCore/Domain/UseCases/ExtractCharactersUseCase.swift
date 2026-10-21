import Foundation

public struct ExtractCharactersUseCase {
    private let repository: DramaRepository
    private let textRepository: AgnesTextRepository

    public init(repository: DramaRepository, textRepository: AgnesTextRepository) {
        self.repository = repository
        self.textRepository = textRepository
    }

    public func execute(projectId: Int64, episodeId: Int64, settings: AgnesSettings) async throws -> Int {
        guard try repository.getProject(projectId) != nil else {
            throw LocalizedMessageError("Project not found")
        }
        guard let episode = try repository.getEpisodeById(episodeId), episode.projectId == projectId else {
            throw LocalizedMessageError("Episode not found")
        }
        let script = episode.scriptContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if script.isEmpty {
            throw LocalizedMessageError("请先为本集创作或改写脚本")
        }

        let existing = try repository.getCharacters(projectId: projectId)
        let content = try await textRepository.complete(
            settings: settings,
            messages: [
                ["role": "system", "content": PromptResolver.resolve(
                    custom: settings.customCharacterExtractPrompt,
                    default: PromptDefaults.characterExtractPrompt
                )],
                ["role": "user", "content": userPrompt(script: script, existing: existing)]
            ],
            temperature: 0.3,
            maxTokens: 4000
        )

        let characters = try parseCharacters(content, projectId: projectId, episodeId: episodeId, existing: existing)
        try repository.upsertCharacters(projectId: projectId, characters: characters)
        return characters.count
    }

    private func userPrompt(script: String, existing: [Character]) -> String {
        let existingHint: String
        let existingIdLine: String
        if existing.isEmpty {
            existingHint = ""
            existingIdLine = ""
        } else {
            let names = existing.map(\.name).joined(separator: "、")
            existingHint = "\n\n项目中已存在角色：\(names)。若剧本中同名角色已存在，请合并更新其信息；若为新角色则创建。"
            existingIdLine = "若角色已存在（名字匹配），请在条目中加 existing_id 字段标记已有角色的 id。\n"
        }
        return """
        请从以下剧本中提取所有角色信息，返回 JSON 数组。
        每个条目包含：name（角色名）、role（主角/配角/龙套）、description（角色描述）、appearance（外貌特征，用于生成角色立绘）、personality（性格特征）。
        \(existingIdLine)只返回 JSON 数组。

        剧本：
        \(script)\(existingHint)
        """
    }

    private func parseCharacters(
        _ content: String,
        projectId: Int64,
        episodeId: Int64,
        existing: [Character]
    ) throws -> [Character] {
        guard let start = content.firstIndex(of: "["), let end = content.lastIndex(of: "]"), start < end else {
            throw LocalizedMessageError("无法解析角色提取结果")
        }
        let slice = String(content[start...end])
        guard let data = slice.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw LocalizedMessageError("无法解析角色提取结果")
        }

        let byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name.trimmingCharacters(in: .whitespacesAndNewlines), $0) })
        let characters: [Character] = items.compactMap { item in
            let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let prior = byName[name]
            return Character(
                id: prior?.id ?? 0,
                projectId: projectId,
                episodeId: episodeId,
                name: name,
                role: kept(item["role"] as? String, prior?.role),
                description: kept(item["description"] as? String, prior?.description),
                appearance: kept(item["appearance"] as? String, prior?.appearance),
                personality: kept(item["personality"] as? String, prior?.personality),
                imageStatus: prior?.imageStatus ?? .pending,
                imageUrl: prior?.imageUrl,
                imageLocalPath: prior?.imageLocalPath,
                imageErrorMessage: prior?.imageErrorMessage,
                createdAt: prior?.createdAt ?? 0,
                updatedAt: prior?.updatedAt ?? 0
            )
        }
        if characters.isEmpty {
            throw LocalizedMessageError("未从剧本中提取到角色")
        }
        return characters
    }

    private func kept(_ incoming: String?, _ previous: String?) -> String {
        let trimmed = incoming?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return previous ?? ""
        }
        return trimmed
    }
}
