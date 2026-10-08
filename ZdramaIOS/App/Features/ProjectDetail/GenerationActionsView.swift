import SwiftUI
import ZdramaCore

/// 生成操作区：全部生成 / 剧本 / 改写 / 分镜 / 出图 / 出视频 / 成片 / 取消。
/// 生成进行中时禁用全部生成按钮（取消按钮仅在运行时可用）。
struct GenerationActionsView: View {
    let isRunning: Bool
    let onGenerate: (String) -> Void
    let onCancel: () -> Void

    private static let actions: [(key: String, title: String, icon: String)] = [
        (GenerationStageKey.full, "全部生成", "sparkles"),
        (GenerationStageKey.text, "剧本", "doc.text"),
        (GenerationStageKey.rewrite, "改写", "arrow.triangle.2.circlepath"),
        (GenerationStageKey.storyboard, "分镜", "rectangle.split.3x3"),
        (GenerationStageKey.image, "出图", "photo"),
        (GenerationStageKey.video, "出视频", "video"),
        (GenerationStageKey.finalVideo, "成片", "film")
    ]

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("生成操作")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.actions, id: \.key) { action in
                    Button {
                        onGenerate(action.key)
                    } label: {
                        Label(action.title, systemImage: action.icon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)
                }
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!isRunning)
            }
        }
    }
}
