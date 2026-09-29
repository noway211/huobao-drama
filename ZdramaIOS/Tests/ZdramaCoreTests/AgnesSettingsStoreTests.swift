import XCTest
@testable import ZdramaCore

final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func get(_ key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }
}

final class AgnesSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var keychain: InMemoryKeychainStore!
    private var store: AgnesSettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "AgnesSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
        keychain = InMemoryKeychainStore()
        store = AgnesSettingsStore(defaults: defaults, keychain: keychain)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        keychain = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testLoadEmptyStoreReturnsDefaults() {
        let loaded = store.load()
        XCTAssertEqual(loaded, AgnesSettings.defaults())
        XCTAssertEqual(AgnesSettings.defaults().apiKey, "")
        XCTAssertEqual(AgnesSettings.defaults().baseUrl, "https://apihub.agnes-ai.com/")
        XCTAssertEqual(AgnesSettings.defaults().textModel, "")
        XCTAssertEqual(AgnesSettings.defaults().imageModel, "agnes-image-2.0-flash")
        XCTAssertEqual(AgnesSettings.defaults().videoModel, "agnes-video-v2.0")
        XCTAssertEqual(AgnesSettings.defaults().requestTimeoutSeconds, 120)
        XCTAssertNil(AgnesSettings.defaults().customScriptCreatePrompt)
        XCTAssertNil(AgnesSettings.defaults().customScriptRewritePrompt)
        XCTAssertNil(AgnesSettings.defaults().customCharacterExtractPrompt)
        XCTAssertNil(AgnesSettings.defaults().customStoryboardPrompt)
    }

    func testSaveLoadRoundTripsApiKey() throws {
        var settings = AgnesSettings.defaults()
        settings.apiKey = "sk-test-key"
        store.save(settings)

        XCTAssertEqual(store.load().apiKey, "sk-test-key")
        XCTAssertEqual(try keychain.get("api_key"), "sk-test-key")
        XCTAssertTrue(store.hasApiKey())
    }

    func testNormalizeBaseURLAppendsSlashAndFallsBackWhenBlank() {
        XCTAssertEqual(
            AgnesSettingsStore.normalizeBaseURL("https://example.com"),
            "https://example.com/"
        )
        XCTAssertEqual(
            AgnesSettingsStore.normalizeBaseURL("https://example.com/"),
            "https://example.com/"
        )
        XCTAssertEqual(
            AgnesSettingsStore.normalizeBaseURL("  https://example.com  "),
            "https://example.com/"
        )
        XCTAssertEqual(
            AgnesSettingsStore.normalizeBaseURL(""),
            AgnesSettings.defaultBaseURL
        )
        XCTAssertEqual(
            AgnesSettingsStore.normalizeBaseURL("   "),
            AgnesSettings.defaultBaseURL
        )
    }

    func testSaveNormalizesBaseURLWithoutSlash() {
        var settings = AgnesSettings.defaults()
        settings.baseUrl = "https://custom.example.com"
        store.save(settings)
        XCTAssertEqual(store.load().baseUrl, "https://custom.example.com/")
        XCTAssertEqual(defaults.string(forKey: "base_url"), "https://custom.example.com/")
    }

    func testBlankCustomPromptLoadsAsNil() {
        let settings = AgnesSettings(
            apiKey: "k",
            baseUrl: AgnesSettings.defaultBaseURL,
            textModel: "",
            imageModel: AgnesSettings.defaultImageModel,
            videoModel: AgnesSettings.defaultVideoModel,
            requestTimeoutSeconds: 120,
            customScriptCreatePrompt: "  ",
            customScriptRewritePrompt: "",
            customCharacterExtractPrompt: " keep me ",
            customStoryboardPrompt: nil
        )
        store.save(settings)

        let loaded = store.load()
        XCTAssertNil(loaded.customScriptCreatePrompt)
        XCTAssertNil(loaded.customScriptRewritePrompt)
        XCTAssertEqual(loaded.customCharacterExtractPrompt, "keep me")
        XCTAssertNil(loaded.customStoryboardPrompt)
        XCTAssertNil(defaults.string(forKey: "custom_script_create_prompt"))
        XCTAssertNil(defaults.string(forKey: "custom_script_rewrite_prompt"))
        XCTAssertEqual(defaults.string(forKey: "custom_character_extract_prompt"), "keep me")
        XCTAssertNil(defaults.string(forKey: "custom_storyboard_prompt"))
    }

    func testHasApiKeyFalseForMissingEmptyAndWhitespace() throws {
        XCTAssertFalse(store.hasApiKey())

        try keychain.set("api_key", value: "")
        XCTAssertFalse(store.hasApiKey())

        try keychain.set("api_key", value: "   \n\t")
        XCTAssertFalse(store.hasApiKey())

        try keychain.set("api_key", value: "present")
        XCTAssertTrue(store.hasApiKey())
    }

    func testSaveAlwaysWritesDefaultTimeout() {
        var settings = AgnesSettings.defaults()
        settings.requestTimeoutSeconds = 30
        store.save(settings)

        XCTAssertEqual(store.load().requestTimeoutSeconds, AgnesSettings.defaultTimeoutSeconds)
        XCTAssertEqual(defaults.integer(forKey: "timeout_seconds"), 120)
    }

    func testSaveTrimsApiKeyAndModels() throws {
        var settings = AgnesSettings.defaults()
        settings.apiKey = "  sk-trim  "
        settings.textModel = "  text-model  "
        settings.imageModel = "  image-model  "
        settings.videoModel = "  video-model  "
        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded.apiKey, "sk-trim")
        XCTAssertEqual(loaded.textModel, "text-model")
        XCTAssertEqual(loaded.imageModel, "image-model")
        XCTAssertEqual(loaded.videoModel, "video-model")
        XCTAssertEqual(try keychain.get("api_key"), "sk-trim")
        XCTAssertEqual(defaults.string(forKey: "text_model"), "text-model")
        XCTAssertEqual(defaults.string(forKey: "image_model"), "image-model")
        XCTAssertEqual(defaults.string(forKey: "video_model"), "video-model")
    }

    func testLoadFallsBackBlankBaseUrlImageAndVideoModels() {
        defaults.set("", forKey: "base_url")
        defaults.set("kept-text", forKey: "text_model")
        defaults.set("   ", forKey: "image_model")
        defaults.set("", forKey: "video_model")

        let loaded = store.load()
        XCTAssertEqual(loaded.baseUrl, AgnesSettings.defaultBaseURL)
        XCTAssertEqual(loaded.textModel, "kept-text")
        XCTAssertEqual(loaded.imageModel, AgnesSettings.defaultImageModel)
        XCTAssertEqual(loaded.videoModel, AgnesSettings.defaultVideoModel)
    }

    func testLoadKeepsEmptyTextModelAndMissingTimeoutDefaultsTo120() {
        defaults.set("", forKey: "text_model")

        let loaded = store.load()
        XCTAssertEqual(loaded.textModel, "")
        XCTAssertNil(defaults.object(forKey: "timeout_seconds"))
        XCTAssertEqual(loaded.requestTimeoutSeconds, 120)
    }
}
