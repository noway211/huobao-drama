import SwiftUI
import ZdramaCore

/// 分镜查看页：卡片列表，每张卡片展示镜头信息，并提供图片/视频提示词的编辑与保存。
struct StoryboardViewerView: View {
    let shots: [StoryboardShot]
    let saveImagePrompt: (Int64, String) -> Bool
    let saveVideoPrompt: (Int64, String) -> Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(shots) { shot in
                    StoryboardShotCard(
                        shot: shot,
                        saveImagePrompt: saveImagePrompt,
                        saveVideoPrompt: saveVideoPrompt
                    )
                }
            }
            .padding()
        }
        .navigationTitle("分镜")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// 单张分镜卡片：镜头信息 + 图片提示词 + 视频提示词（各有独立保存按钮）。
private struct StoryboardShotCard: View {
    let shot: StoryboardShot
    let saveImagePrompt: (Int64, String) -> Bool
    let saveVideoPrompt: (Int64, String) -> Bool

    @State private var imagePrompt: String
    @State private var videoPrompt: String
    @State private var savedMessage: String?

    init(
        shot: StoryboardShot,
        saveImagePrompt: @escaping (Int64, String) -> Bool,
        saveVideoPrompt: @escaping (Int64, String) -> Bool
    ) {
        self.shot = shot
        self.saveImagePrompt = saveImagePrompt
        self.saveVideoPrompt = saveVideoPrompt
        _imagePrompt = State(initialValue: shot.imagePrompt)
        _videoPrompt = State(initialValue: shot.videoPrompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第 \(shot.shotNumber) 镜")
                .font(.headline)
            Text(shotDetails)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            TextField("图片提示词", text: $imagePrompt, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            Button {
                if saveImagePrompt(shot.id, imagePrompt) {
                    savedMessage = "图片提示词已保存"
                }
            } label: {
                Text("保存图片提示词")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(imagePrompt == shot.imagePrompt)
            TextField("视频提示词", text: $videoPrompt, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            Button {
                if saveVideoPrompt(shot.id, videoPrompt) {
                    savedMessage = "视频提示词已保存"
                }
            } label: {
                Text("保存视频提示词")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(videoPrompt == shot.videoPrompt)
            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var shotDetails: String {
        var parts: [String] = []
        if !shot.scene.isEmpty {
            parts.append("场景：\(shot.scene)")
        }
        if !shot.action.isEmpty {
            parts.append("表演：\(shot.action)")
        }
        if !shot.dialogue.isEmpty {
            parts.append("台词：\(shot.dialogue)")
        }
        if !shot.camera.isEmpty {
            parts.append("镜头：\(shot.camera)")
        }
        return parts.joined(separator: "｜")
    }
}
