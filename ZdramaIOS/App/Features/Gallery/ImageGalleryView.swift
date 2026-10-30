import SwiftUI
import UIKit
import ZdramaCore

/// 图库页：网格展示各镜头的生成图片，本地文件优先，其次远程 URL。只读。
struct ImageGalleryView: View {
    let shots: [StoryboardShot]
    let resolvePath: (String?) -> String?

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
            image(shot)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("第\(shot.shotNumber)镜")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 本地文件直接用 UIImage 读取，并按图片本身的宽高比展示。
    /// AsyncImage 对 file:// 会停在占位图，所以只留给远程地址。
    @ViewBuilder
    private func image(_ shot: StoryboardShot) -> some View {
        if let path = resolvePath(shot.imageLocalPath), !path.isEmpty,
           FileManager.default.fileExists(atPath: path),
           let uiImage = UIImage(contentsOfFile: path), uiImage.size.height > 0 {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .aspectRatio(uiImage.size.width / uiImage.size.height, contentMode: .fit)
        } else {
            AsyncImage(url: remoteURL(shot)) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
            } placeholder: {
                placeholder(shot)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
            }
        }
    }

    private func placeholder(_ shot: StoryboardShot) -> some View {
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

    private func remoteURL(_ shot: StoryboardShot) -> URL? {
        guard let urlString = shot.imageUrl, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}
