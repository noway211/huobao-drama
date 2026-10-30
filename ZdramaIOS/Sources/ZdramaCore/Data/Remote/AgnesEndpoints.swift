import Foundation

public enum AgnesEndpoints {
    public static func chatCompletions(baseURL: String) -> URL {
        url(baseURL, path: "v1/chat/completions")
    }

    public static func imagesGenerations(baseURL: String) -> URL {
        url(baseURL, path: "v1/images/generations")
    }

    public static func videos(baseURL: String) -> URL {
        url(baseURL, path: "v1/videos")
    }

    /// 2.5 的查询不走 v1/videos/{id}。keyframe 必须带 model_name，
    /// 而且要用创建响应里的 video_id，用 task_id 会回 404。
    public static func video(baseURL: String, videoId: String, modelName: String) -> URL {
        var components = URLComponents(
            url: url(baseURL, path: "agnesapi"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "video_id", value: videoId),
            URLQueryItem(name: "model_name", value: modelName)
        ]
        return components?.url ?? url(baseURL, path: "agnesapi")
    }

    private static func url(_ baseURL: String, path: String) -> URL {
        let normalized = AgnesSettingsStore.normalizeBaseURL(baseURL)
        return URL(string: normalized + path)!
    }
}
