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

    public static func video(baseURL: String, taskId: String) -> URL {
        url(baseURL, path: "v1/videos/\(taskId)")
    }

    private static func url(_ baseURL: String, path: String) -> URL {
        let normalized = AgnesSettingsStore.normalizeBaseURL(baseURL)
        return URL(string: normalized + path)!
    }
}
