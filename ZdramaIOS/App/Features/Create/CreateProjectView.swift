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
                PromptEditor(text: $prompt)
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

/// 故事提示词：按当前宽度折行后撑开高度，最多 8 行；更长的内容在框内滚动，不再用 lineLimit 留出空白行。
private struct PromptEditor: View {
    @Binding var text: String
    @State private var width: CGFloat = 0

    private static let font = UIFont.preferredFont(forTextStyle: .body)
    private static let minLines = 3
    private static let maxLines = 8
    private static var lineHeight: CGFloat { font.lineHeight }
    private static var verticalInset: CGFloat { 16 }

    var body: some View {
        let cap = Self.lineHeight * CGFloat(Self.maxLines) + Self.verticalInset
        let floor = Self.lineHeight * CGFloat(Self.minLines) + Self.verticalInset
        let measured = Self.measuredHeight(text: text, width: width)
        let height = min(max(measured, floor), cap)
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .scrollDisabled(measured <= cap)
            .autocorrectionDisabled()
            .frame(height: height)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PromptEditorWidthKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(PromptEditorWidthKey.self) { width = $0 }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("故事提示词")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }

    private static func measuredHeight(text: String, width: CGFloat) -> CGFloat {
        guard width > 1 else { return lineHeight * CGFloat(minLines) + verticalInset }
        let content = text.isEmpty ? " " : text
        let bounds = (content as NSString).boundingRect(
            with: CGSize(width: width - 10, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.height) + verticalInset
    }
}

private struct PromptEditorWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
