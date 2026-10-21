import SwiftUI
import UIKit
import ZdramaCore

/// 项目角色列表：展示已提取角色，并为单个角色重新生成肖像。
@MainActor
struct CharacterListView: View {
    @ObservedObject var container: AppContainer
    let projectId: Int64

    @State private var characters: [Character] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("重试") { reload() }
                }
            } else if characters.isEmpty {
                ContentUnavailableView {
                    Label("项目角色", systemImage: "person.2")
                } description: {
                    Text("该项目暂无角色，请先在项目详情页提取角色")
                }
            } else {
                List(characters) { character in
                    characterRow(character)
                }
            }
        }
        .navigationTitle("项目角色")
        .onAppear { reload() }
    }

    private func characterRow(_ character: Character) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                portrait(character)
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.name)
                        .font(.headline)
                    Text(character.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "角色定位未填" : character.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            labeled("简介", character.description)
            labeled("外貌", character.appearance)
            labeled("性格", character.personality)
            if let error = character.imageErrorMessage,
               !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("生成图片") {
                Task {
                    guard let episode = try? container.repository.getEpisodeForProject(projectId) else { return }
                    await container.coordinator.enqueue(
                        projectId: projectId,
                        episodeId: episode.id,
                        stage: "\(GenerationStageKey.characterImagePrefix)\(character.id)",
                        forceRegenerate: true
                    )
                    reload()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func portrait(_ character: Character) -> some View {
        if let path = character.imageLocalPath,
           FileManager.default.fileExists(atPath: path),
           let image = platformImage(path: path) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text(statusText(character.imageStatus))
                .font(.caption)
                .frame(width: 72, height: 72)
                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.body)
        }
    }

    private func statusText(_ status: AssetStatus) -> String {
        switch status {
        case .pending: return "待生成"
        case .processing: return "生成中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }

    private func platformImage(path: String) -> Image? {
        guard let uiImage = UIImage(contentsOfFile: path) else { return nil }
        return Image(uiImage: uiImage)
    }

    private func reload() {
        do {
            characters = try container.repository.getCharacters(projectId: projectId)
            loadError = nil
        } catch {
            loadError = "加载失败：\(error.localizedDescription)"
        }
    }
}
