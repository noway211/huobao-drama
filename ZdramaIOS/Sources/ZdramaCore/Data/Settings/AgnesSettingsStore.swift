import Foundation
import Security

public protocol KeychainStore: Sendable {
    func get(_ key: String) throws -> String?
    func set(_ key: String, value: String) throws
}

public struct SystemKeychainStore: KeychainStore, Sendable {
    private let service = "com.huobao.zdrama"

    public init() {}

    public func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
            return
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
    }
}

public final class AgnesSettingsStore: @unchecked Sendable {
    private enum Keys {
        static let apiKey = "api_key"
        static let baseURL = "base_url"
        static let textModel = "text_model"
        static let imageModel = "image_model"
        static let videoModel = "video_model"
        static let timeoutSeconds = "timeout_seconds"
        static let customScriptCreatePrompt = "custom_script_create_prompt"
        static let customScriptRewritePrompt = "custom_script_rewrite_prompt"
        static let customCharacterExtractPrompt = "custom_character_extract_prompt"
        static let customStoryboardPrompt = "custom_storyboard_prompt"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    public init(defaults: UserDefaults, keychain: KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain
    }

    public func load() -> AgnesSettings {
        let fallback = AgnesSettings.defaults()
        return AgnesSettings(
            apiKey: (try? keychain.get(Keys.apiKey)) ?? fallback.apiKey,
            baseUrl: blankFallingBack(defaults.string(forKey: Keys.baseURL), to: fallback.baseUrl),
            textModel: defaults.string(forKey: Keys.textModel) ?? fallback.textModel,
            imageModel: blankFallingBack(defaults.string(forKey: Keys.imageModel), to: fallback.imageModel),
            videoModel: blankFallingBack(defaults.string(forKey: Keys.videoModel), to: fallback.videoModel),
            requestTimeoutSeconds: loadTimeoutSeconds(fallback: fallback.requestTimeoutSeconds),
            customScriptCreatePrompt: defaults.string(forKey: Keys.customScriptCreatePrompt),
            customScriptRewritePrompt: defaults.string(forKey: Keys.customScriptRewritePrompt),
            customCharacterExtractPrompt: defaults.string(forKey: Keys.customCharacterExtractPrompt),
            customStoryboardPrompt: defaults.string(forKey: Keys.customStoryboardPrompt)
        )
    }

    public func save(_ settings: AgnesSettings) throws {
        try keychain.set(Keys.apiKey, value: settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        defaults.set(Self.normalizeBaseURL(settings.baseUrl), forKey: Keys.baseURL)
        defaults.set(settings.textModel.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.textModel)
        defaults.set(settings.imageModel.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.imageModel)
        defaults.set(settings.videoModel.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.videoModel)
        defaults.set(AgnesSettings.defaultTimeoutSeconds, forKey: Keys.timeoutSeconds)
        defaults.set(trimmedOrNil(settings.customScriptCreatePrompt), forKey: Keys.customScriptCreatePrompt)
        defaults.set(trimmedOrNil(settings.customScriptRewritePrompt), forKey: Keys.customScriptRewritePrompt)
        defaults.set(trimmedOrNil(settings.customCharacterExtractPrompt), forKey: Keys.customCharacterExtractPrompt)
        defaults.set(trimmedOrNil(settings.customStoryboardPrompt), forKey: Keys.customStoryboardPrompt)
    }

    public func hasApiKey() -> Bool {
        !load().apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? AgnesSettings.defaultBaseURL : trimmed
        return resolved.hasSuffix("/") ? resolved : resolved + "/"
    }

    private func loadTimeoutSeconds(fallback: Int) -> Int {
        guard defaults.object(forKey: Keys.timeoutSeconds) != nil else {
            return fallback
        }
        return defaults.integer(forKey: Keys.timeoutSeconds)
    }

    private func blankFallingBack(_ value: String?, to fallback: String) -> String {
        let resolved = value ?? fallback
        return resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : resolved
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
