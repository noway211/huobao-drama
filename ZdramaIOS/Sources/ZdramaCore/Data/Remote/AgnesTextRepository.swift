import Foundation

public struct AgnesTextRepository: Sendable {
    private let client: AgnesHTTPClient

    public init(client: AgnesHTTPClient) {
        self.client = client
    }

    public func generateScript(
        settings: AgnesSettings,
        project: DramaProject,
        storyPrompt: String
    ) async throws -> String {
        try AgnesRequest.requireTextModel(settings)
        let json = try await postChat(
            settings: settings,
            messages: [
                ["role": "system", "content": PromptResolver.resolve(
                    custom: settings.customScriptCreatePrompt,
                    default: PromptDefaults.scriptCreatePrompt
                )],
                ["role": "user", "content": buildUserPrompt(project: project, storyPrompt: storyPrompt)]
            ],
            temperature: 0.7,
            maxTokens: 4000
        )
        let text = ChatResponseTextExtractor.extract(json)
        if AgnesRequest.isBlank(text) {
            throw AgnesClientError.emptyScript
        }
        return text
    }

    public func rewriteScript(settings: AgnesSettings, rawContent: String) async throws -> String {
        try AgnesRequest.requireTextModel(settings)
        let json = try await postChat(
            settings: settings,
            messages: [
                ["role": "system", "content": PromptResolver.resolve(
                    custom: settings.customScriptRewritePrompt,
                    default: PromptDefaults.scriptRewritePrompt
                )],
                ["role": "user", "content": buildRewriteUserPrompt(rawContent)]
            ],
            temperature: 0.7,
            maxTokens: 6000
        )
        let text = ChatResponseTextExtractor.extract(json)
        if AgnesRequest.isBlank(text) {
            throw AgnesClientError.emptyRewrite
        }
        return text
    }

    public func ping(settings: AgnesSettings) async throws {
        try AgnesRequest.requireTextModel(settings)
        let request = try AgnesRequest.jsonPOST(
            url: AgnesEndpoints.chatCompletions(baseURL: settings.baseUrl),
            apiKey: settings.apiKey,
            body: AgnesRequest.chatBody(
                model: settings.textModel,
                messages: [["role": "user", "content": "ping"]],
                temperature: 0,
                maxTokens: 8
            )
        )
        try await AgnesRequest.sendExpecting2xx(client: client, request: request)
    }

    private func postChat(
        settings: AgnesSettings,
        messages: [[String: String]],
        temperature: Double,
        maxTokens: Int
    ) async throws -> Any {
        let request = try AgnesRequest.jsonPOST(
            url: AgnesEndpoints.chatCompletions(baseURL: settings.baseUrl),
            apiKey: settings.apiKey,
            body: AgnesRequest.chatBody(
                model: settings.textModel,
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens
            )
        )
        return try await AgnesRequest.sendJSON(client: client, request: request)
    }

    private func buildUserPrompt(project: DramaProject, storyPrompt: String) -> String {
        """
        请根据以下项目信息创作一部短视频短剧剧本。

        项目标题：\(project.title)
        故事提示词：\(storyPrompt)
        风格：\(project.style)
        目标受众：\(project.targetAudience)
        画幅比例：\(project.aspectRatio)
        镜头数量：\(project.shotCount)
        单镜头时长：\(project.shotDurationSeconds)秒
        """
    }

    private func buildRewriteUserPrompt(_ rawContent: String) -> String {
        """
        请将以下内容改写为格式化短剧剧本。

        【原始内容】
        \(rawContent)
        """
    }
}
