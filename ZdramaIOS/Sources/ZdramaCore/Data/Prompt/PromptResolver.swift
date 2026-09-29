import Foundation

public enum PromptResolver {
    public static func resolve(custom: String?, default defaultValue: String) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}
