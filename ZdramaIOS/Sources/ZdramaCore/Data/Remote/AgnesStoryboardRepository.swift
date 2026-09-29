import Foundation

public struct AgnesStoryboardRepository: Sendable {
    private let client: AgnesHTTPClient

    public init(client: AgnesHTTPClient) {
        self.client = client
    }

    public func generateStoryboards(
        settings: AgnesSettings,
        project: DramaProject,
        script: String
    ) async throws -> [StoryboardShot] {
        try AgnesRequest.requireTextModel(settings)
        let request = try AgnesRequest.jsonPOST(
            url: AgnesEndpoints.chatCompletions(baseURL: settings.baseUrl),
            apiKey: settings.apiKey,
            body: AgnesRequest.chatBody(
                model: settings.textModel,
                messages: [
                    [
                        "role": "system",
                        "content": PromptResolver.resolve(
                            custom: settings.customStoryboardPrompt,
                            default: PromptDefaults.storyboardPrompt
                        )
                    ],
                    ["role": "user", "content": buildUserPrompt(project: project, script: script)]
                ],
                temperature: 0.3,
                maxTokens: 10000
            )
        )
        let json = try await AgnesRequest.sendJSON(client: client, request: request)
        let content = ChatResponseTextExtractor.extractFinalContent(json)
        if AgnesRequest.isBlank(content) && ChatResponseTextExtractor.finishReason(json) == "length" {
            throw AgnesClientError.truncatedStoryboard
        }
        let items = try StoryboardJSONParser.parse(content)
        if items.isEmpty {
            throw AgnesClientError.emptyStoryboard
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return try items.enumerated().map { index, item in
            try mapItem(item, index: index, project: project, now: now)
        }
    }

    private func mapItem(
        _ item: ParsedStoryboardItem,
        index: Int,
        project: DramaProject,
        now: Int64
    ) throws -> StoryboardShot {
        let names = item.characterNames ?? []
        let characterIds: String?
        if names.isEmpty {
            characterIds = nil
        } else {
            let data = try JSONSerialization.data(withJSONObject: names)
            characterIds = String(data: data, encoding: .utf8)
        }
        return StoryboardShot(
            id: 0,
            projectId: project.id,
            episodeId: nil,
            shotNumber: item.shotNumber.flatMap { Int($0) } ?? (index + 1),
            scene: item.scene,
            action: item.action,
            dialogue: item.dialogue,
            camera: item.camera,
            imagePrompt: item.imagePrompt,
            videoPrompt: item.videoPrompt,
            durationSeconds: item.durationSeconds.flatMap { Int($0) } ?? project.shotDurationSeconds,
            characterNames: names,
            characterIds: characterIds,
            imageStatus: .pending,
            imageUrl: nil,
            imageLocalPath: nil,
            imageErrorMessage: nil,
            videoStatus: .pending,
            videoTaskId: nil,
            videoUrl: nil,
            videoLocalPath: nil,
            videoErrorMessage: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func buildUserPrompt(project: DramaProject, script: String) -> String {
        let sceneCount = StoryboardJSONParser.countSceneHeaders(script)
        let shotCountHint: String
        if sceneCount > 0 {
            shotCountHint = "Script contains \(sceneCount) scene headers (## S01, ## S02 ...). Generate exactly one storyboard shot per scene, in order."
        } else {
            shotCountHint = "Expected shot count: \(project.shotCount)"
        }
        return """
        Project title: \(project.title)
        Aspect ratio: \(project.aspectRatio)
        \(shotCountHint)
        Default shot duration seconds: \(project.shotDurationSeconds)

        Script:
        \(script)

        Return only a JSON array. Each item must use these keys: shot_number, scene, action, dialogue, camera, image_prompt, video_prompt, duration_seconds, character_names. character_names must be an array of character names that appear in this shot (use the exact character name strings from the script), or [] if no characters appear.
        """
    }
}
