import AVKit
import SwiftUI
import ZdramaCore

/// 视频播放页：shots 模式逐镜播放（本地文件优先，回退远程视频），final 模式播放成片（本地文件）。
struct VideoPlayerView: View {
    enum Mode {
        /// 逐镜播放：上一镜 / 下一镜切换。
        case shots
        /// 播放合成的成片。
        case final
    }

    let mode: Mode
    let episode: Episode
    let shots: [StoryboardShot]

    @State private var currentIndex = 0
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            playerArea
            controls
        }
        .navigationTitle(mode == .shots ? "镜头视频" : "成片")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: currentIndex) {
            rebuildPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }

    // MARK: - 播放区域

    @ViewBuilder
    private var playerArea: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                placeholderText,
                systemImage: "video.slash",
                description: Text("请先完成对应阶段的生成")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 控制区

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            switch mode {
            case .shots:
                HStack {
                    Button {
                        move(by: -1)
                    } label: {
                        Label("上一镜", systemImage: "chevron.left")
                    }
                    .disabled(currentIndex <= 0)
                    Spacer()
                    if let shot = currentShot {
                        Text("第 \(shot.shotNumber)/\(shots.count) 镜")
                            .font(.subheadline)
                    }
                    Spacer()
                    Button {
                        move(by: 1)
                    } label: {
                        Label("下一镜", systemImage: "chevron.right")
                    }
                    .disabled(currentIndex >= shots.count - 1)
                }
                if let shot = currentShot, !shot.videoPrompt.isEmpty {
                    Text("提示词：\(shot.videoPrompt)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .final:
                HStack {
                    Label(episode.title, systemImage: "film")
                        .font(.subheadline)
                    Spacer()
                    Text("成片")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // MARK: - 派生状态

    private var currentShot: StoryboardShot? {
        guard shots.indices.contains(currentIndex) else { return nil }
        return shots[currentIndex]
    }

    /// 当前要播放的视频地址：镜头视频本地优先（回退远程），成片仅本地。
    private var currentURL: URL? {
        switch mode {
        case .shots:
            guard let shot = currentShot else { return nil }
            if let path = shot.videoLocalPath, !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            guard let urlString = shot.videoUrl, !urlString.isEmpty else { return nil }
            return URL(string: urlString)
        case .final:
            guard let path = episode.finalVideoLocalPath, !path.isEmpty,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    private var placeholderText: String {
        switch mode {
        case .shots: return "该镜头尚未生成视频"
        case .final: return "成片尚未生成"
        }
    }

    // MARK: - 动作

    private func move(by delta: Int) {
        let next = currentIndex + delta
        guard shots.indices.contains(next) else { return }
        player?.pause()
        currentIndex = next
    }

    private func rebuildPlayer() {
        player?.pause()
        if let url = currentURL {
            player = AVPlayer(url: url)
        } else {
            player = nil
        }
    }
}
