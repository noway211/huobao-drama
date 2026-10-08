import SwiftUI
import ZdramaCore

/// 设置页：API Key、Base URL、模型配置、连通性测试与提示词入口。
@MainActor
struct SettingsView: View {
    @ObservedObject var container: AppContainer

    @State private var apiKey: String
    @State private var baseUrl: String
    @State private var textModel: String
    @State private var imageModel: String
    @State private var videoModel: String
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var isTesting = false

    init(container: AppContainer) {
        self.container = container
        let settings = container.settingsStore.load()
        _apiKey = State(initialValue: settings.apiKey)
        _baseUrl = State(initialValue: settings.baseUrl)
        _textModel = State(initialValue: settings.textModel)
        _imageModel = State(initialValue: settings.imageModel)
        _videoModel = State(initialValue: settings.videoModel)
    }

    var body: some View {
        Form {
            Section("接口配置") {
                SecureField("API Key", text: $apiKey)
                TextField("Base URL", text: $baseUrl)
                    .autocorrectionDisabled()
            }
            Section("模型") {
                TextField("文本模型", text: $textModel)
                TextField("图片模型", text: $imageModel)
                TextField("视频模型", text: $videoModel)
            }
            Section("操作") {
                Button("保存") { save() }
                Button(isTesting ? "测试中…" : "测试文本连通") { testPing() }
                    .disabled(isTesting)
                if let feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(feedbackIsError ? .red : .green)
                }
            }
            Section {
                NavigationLink("提示词") { ManagePromptsView(container: container) }
            }
        }
        .navigationTitle("设置")
    }

    private func currentSettings() -> AgnesSettings {
        let existing = container.settingsStore.load()
        return AgnesSettings(
            apiKey: apiKey,
            baseUrl: baseUrl,
            textModel: textModel,
            imageModel: imageModel,
            videoModel: videoModel,
            requestTimeoutSeconds: existing.requestTimeoutSeconds,
            customScriptCreatePrompt: existing.customScriptCreatePrompt,
            customScriptRewritePrompt: existing.customScriptRewritePrompt,
            customCharacterExtractPrompt: existing.customCharacterExtractPrompt,
            customStoryboardPrompt: existing.customStoryboardPrompt
        )
    }

    private func save() {
        container.settingsStore.save(currentSettings())
        feedbackIsError = false
        feedback = "已保存"
    }

    private func testPing() {
        isTesting = true
        feedback = nil
        Task {
            defer { isTesting = false }
            do {
                try await container.textRepository.ping(settings: currentSettings())
                feedbackIsError = false
                feedback = "连接成功"
            } catch {
                feedbackIsError = true
                feedback = "连接失败：\(error.localizedDescription)"
            }
        }
    }
}
