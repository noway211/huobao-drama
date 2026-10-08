import SwiftUI
import ZdramaCore

/// 图库页：网格展示各镜头的生成图片，本地文件优先，其次远程 URL。只读。
struct ImageGalleryView: View {
    let shots: [StoryboardShot]

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(shots) { shot in
                    tile(shot)
                }
            }
            .padding()
        }
        .navigationTitle("图库")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func tile(_ shot: StoryboardShot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: imageURL(shot)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.15)
                    if shot.imageStatus == .processing {
                        ProgressView()
                    } else if shot.imageStatus == .failed {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("第\(shot.shotNumber)镜")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 本地文件存在时返回本地 URL，否则回退远程地址；均无则返回 nil（显示占位）。
    private func imageURL(_ shot: StoryboardShot) -> URL? {
        if let path = shot.imageLocalPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let urlString = shot.imageUrl, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}
