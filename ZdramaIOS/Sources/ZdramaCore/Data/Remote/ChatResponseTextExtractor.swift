import Foundation

public enum ChatResponseTextExtractor {
    public static func finishReason(_ json: Any) -> String {
        guard let root = asObject(json) else { return "" }
        let choices = arrayValue(root, "choices")
        guard let firstChoice = firstObject(choices) else { return "" }
        return stringValue(firstChoice, "finish_reason") ?? ""
    }

    public static func extractFinalContent(_ json: Any) -> String {
        guard let root = asObject(json) else { return "" }
        var candidates: [String] = []

        if let outputText = stringValue(root, "output_text") {
            candidates.append(outputText)
        }

        if let choices = arrayValue(root, "choices") {
            for choice in choices {
                guard let choiceObject = asObject(choice) else { continue }

                if let choiceText = stringValue(choiceObject, "text") {
                    candidates.append(choiceText)
                }

                if let message = objectValue(choiceObject, "message") {
                    if let content = message["content"] {
                        candidates.append(extractContentText(content))
                    }
                    if let messageText = stringValue(message, "text") {
                        candidates.append(messageText)
                    }
                }

                if let delta = objectValue(choiceObject, "delta") {
                    if let content = delta["content"] {
                        candidates.append(extractContentText(content))
                    }
                }
            }
        }

        if let output = arrayValue(root, "output") {
            for item in output {
                candidates.append(extractContentText(item))
            }
        }

        return firstNonBlank(candidates)
    }

    public static func extract(_ json: Any) -> String {
        let finalContent = extractFinalContent(json)
        if isNotBlank(finalContent) { return finalContent }
        guard let root = asObject(json) else { return "" }

        var candidates: [String] = []
        if let choices = arrayValue(root, "choices") {
            for choice in choices {
                guard let choiceObject = asObject(choice) else { continue }
                guard let message = objectValue(choiceObject, "message") else { continue }
                if let reasoningContent = message["reasoning_content"] {
                    candidates.append(extractContentText(reasoningContent))
                }
            }
        }
        return firstNonBlank(candidates)
    }

    private static func extractContentText(_ value: Any) -> String {
        if value is NSNull { return "" }
        if let string = value as? String { return string }
        if let array = asArray(value) { return extractArrayText(array) }
        if let object = asObject(value) { return extractObjectText(object) }
        return ""
    }

    private static func extractArrayText(_ array: [Any]) -> String {
        var parts: [String] = []
        for item in array {
            let text = extractContentText(item)
            if isNotBlank(text) {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func extractObjectText(_ object: [String: Any]) -> String {
        if let text = stringValue(object, "text") { return text }
        if let outputText = stringValue(object, "output_text") { return outputText }
        if let contentText = stringValue(object, "content") { return contentText }
        if let content = object["content"], let array = asArray(content) {
            return extractArrayText(array)
        }
        return ""
    }

    private static func firstObject(_ array: [Any]?) -> [String: Any]? {
        guard let array, let first = array.first else { return nil }
        return asObject(first)
    }

    private static func firstNonBlank(_ values: [String]) -> String {
        for value in values {
            if isNotBlank(value) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func isNotBlank(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func stringValue(_ object: [String: Any], _ key: String) -> String? {
        guard let value = object[key], !(value is NSNull) else { return nil }
        return value as? String
    }

    private static func objectValue(_ object: [String: Any], _ key: String) -> [String: Any]? {
        guard let value = object[key] else { return nil }
        return asObject(value)
    }

    private static func arrayValue(_ object: [String: Any], _ key: String) -> [Any]? {
        asArray(object[key])
    }

    private static func asObject(_ json: Any) -> [String: Any]? {
        if json is NSNull { return nil }
        if let object = json as? [String: Any] {
            return object
        }
        if let data = json as? Data {
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        if let nsDict = json as? NSDictionary {
            var object: [String: Any] = [:]
            for (key, value) in nsDict {
                if let key = key as? String {
                    object[key] = value
                }
            }
            return object
        }
        return nil
    }

    private static func asArray(_ value: Any?) -> [Any]? {
        guard let value, !(value is NSNull) else { return nil }
        if let array = value as? [Any] {
            return array
        }
        if let nsArray = value as? NSArray {
            return nsArray.map { $0 as Any }
        }
        // Homogeneous Swift arrays (e.g. [[String: String]]) do not cast to [Any].
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .collection else { return nil }
        return mirror.children.map(\.value)
    }
}
