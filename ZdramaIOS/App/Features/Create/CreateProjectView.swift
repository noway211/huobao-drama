import SwiftUI
import ZdramaCore

/// 新建项目页：填写标题、故事提示词、风格、受众、画幅与拍摄参数，保存后进入详情。
@MainActor
struct CreateProjectView: View {
    @ObservedObject var container: AppContainer
    @Binding var path: [AppRoute]

    @State private var title = ""
    @State private var prompt = ""
    @State private var style = "现代短剧"
    @State private var audience = "大众受众"
    @State private var aspect = "9:16"
    @State private var shotCount = "8"
    @State private var duration = "5"
    @State private var errorMessage: String?
    @State private var isSaving = false

    private static let styles = ["现代短剧", "古装", "悬疑", "都市", "甜宠"]
    private static let audiences = ["大众受众", "女性向", "男性向", "青少年"]
    private static let aspects = ["9:16", "16:9", "1:1"]

    init(container: AppContainer, path: Binding<[AppRoute]>) {
        self.container = container
        _path = path
    }

    var body: some View {
        Form {
            Section("剧本信息") {
                TextField("标题", text: $title)
                TextField("故事提示词", text: $prompt, axis: .vertical)
                    .lineLimit(6...10)
                Picker("风格", selection: $style) {
                    ForEach(Self.styles, id: \.self) { Text($0) }
                }
                Picker("目标受众", selection: $audience) {
                    ForEach(Self.audiences, id: \.self) { Text($0) }
                }
                Picker("画幅比例", selection: $aspect) {
                    ForEach(Self.aspects, id: \.self) { Text($0) }
                }
            }
            Section("拍摄参数") {
                TextField("镜头数", text: $shotCount)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                TextField("单镜头时长（秒）", text: $duration)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
            }
            Section {
                Button(isSaving ? "保存中…" : "保存") { save() }
                    .disabled(isSaving)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("新建剧集")
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "请输入标题"
            return
        }
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "请输入故事提示词"
            return
        }
        guard let shots = Int(shotCount.trimmingCharacters(in: .whitespacesAndNewlines)), shots > 0 else {
            errorMessage = "镜头数必须为大于 0 的整数"
            return
        }
        guard let durationSeconds = Int(duration.trimmingCharacters(in: .whitespacesAndNewlines)), durationSeconds > 0 else {
            errorMessage = "单镜头时长必须为大于 0 的整数"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            let id = try container.createDrama(
                title: trimmedTitle,
                prompt: trimmedPrompt,
                style: style,
                audience: audience,
                aspect: aspect,
                shotCount: shots,
                duration: durationSeconds
            )
            isSaving = false
            path.append(.detail(id))
        } catch {
            isSaving = false
            errorMessage = "创建失败：\(error.localizedDescription)"
        }
    }
}
