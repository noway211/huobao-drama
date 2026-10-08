import SwiftUI
import ZdramaCore

/// 项目详情页：头部信息、生成操作区、进度卡与内容查看入口。
/// 每 1.5 秒自动刷新项目与分镜数据，生成进行中禁用生成按钮。
@MainActor
struct ProjectDetailView: View {
    @ObservedObject var container: AppContainer
    @Binding var path: [AppRoute]
    @StateObject private var viewModel: ProjectDetailViewModel

    @State private var showDeleteConfirm = false
    @State private var deleteError: String?

    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    init(container: AppContainer, projectId: Int64, path: Binding<[AppRoute]>) {
        self.container = container
        _path = path
        _viewModel = StateObject(
            wrappedValue: ProjectDetailViewModel(
                projectId: projectId,
                repository: container.repository,
                coordinator: container.coordinator,
                settingsStore: container.settingsStore
            )
        )
    }

    var body: some View {
        Group {
            if let project = viewModel.project {
                content(project)
            } else if let loadError = viewModel.loadError {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("重试") { viewModel.refresh() }
                }
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("删除") {
                    showDeleteConfirm = true
                }
                .tint(.red)
            }
        }
        .onAppear { viewModel.refresh() }
        .onReceive(refreshTimer) { _ in viewModel.refresh() }
        .alert(
            "提示",
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.dismissAlert() } }
            )
        ) {
            Button("确定", role: .cancel) { viewModel.dismissAlert() }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .confirmationDialog(
            "已存在生成结果",
            isPresented: Binding(
                get: { viewModel.pendingOverwriteStage != nil },
                set: { if !$0 { viewModel.cancelOverwrite() } }
            ),
            titleVisibility: .visible
        ) {
            Button("覆盖重新生成", role: .destructive) { viewModel.confirmOverwrite() }
            Button("取消", role: .cancel) { viewModel.cancelOverwrite() }
        } message: {
            Text("目标内容已存在，重新生成将覆盖现有结果，是否继续？")
        }
        .confirmationDialog(
            "删除项目",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { deleteProject() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除「\(viewModel.title)」及其全部数据，此操作不可恢复。")
        }
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - 内容

    private func content(_ project: DramaProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(project)
                GenerationActionsView(
                    isRunning: viewModel.isGenerating,
                    onGenerate: { viewModel.generate($0) },
                    onCancel: { viewModel.cancel() }
                )
                GenerationProgressCard(project: project, progress: viewModel.progress)
                if viewModel.episode != nil {
                    linksSection()
                }
            }
            .padding()
        }
    }

    private func header(_ project: DramaProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.title)
                .font(.title2.bold())
            HStack(spacing: 8) {
                chip(project.style)
                chip(project.aspectRatio)
                chip("\(project.shotCount) 镜头")
                chip(project.status.displayName)
            }
            if !project.prompt.isEmpty {
                Text(project.prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.gray.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    // MARK: - 内容入口

    @ViewBuilder
    private func linksSection() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("内容")
                .font(.headline)
                .padding(.bottom, 4)
            if viewModel.hasScript {
                linkRow("查看剧本", systemImage: "doc.text") {
                    ScriptViewerView(episode: viewModel.episode)
                }
            } else {
                unavailableRow("查看剧本", systemImage: "doc.text")
            }
            if !viewModel.shots.isEmpty {
                linkRow("分镜", systemImage: "rectangle.split.3x3") {
                    StoryboardViewerView(
                        shots: viewModel.shots,
                        saveImagePrompt: { shotId, prompt in
                            viewModel.saveImagePrompt(shotId: shotId, prompt: prompt)
                        },
                        saveVideoPrompt: { shotId, prompt in
                            viewModel.saveVideoPrompt(shotId: shotId, prompt: prompt)
                        }
                    )
                }
            } else {
                unavailableRow("分镜", systemImage: "rectangle.split.3x3")
            }
            if viewModel.hasGallery {
                linkRow("图库", systemImage: "photo.on.rectangle") {
                    ImageGalleryView(shots: viewModel.shots)
                }
            } else {
                unavailableRow("图库", systemImage: "photo.on.rectangle")
            }
            if viewModel.hasShotVideos {
                linkRow("镜头视频", systemImage: "video") {
                    VideoPlayerView(mode: .shots, episode: viewModel.episode!, shots: viewModel.shots)
                }
            } else {
                unavailableRow("镜头视频", systemImage: "video")
            }
            if viewModel.hasFinalVideo {
                linkRow("成片", systemImage: "film") {
                    VideoPlayerView(mode: .final, episode: viewModel.episode!, shots: viewModel.shots)
                }
            } else {
                unavailableRow("成片", systemImage: "film")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func linkRow<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }

    private func unavailableRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("尚未生成")
                .font(.footnote)
        }
        .padding(.vertical, 4)
        .foregroundStyle(.secondary)
    }

    // MARK: - 删除

    private func deleteProject() {
        guard let project = viewModel.project else { return }
        Task {
            do {
                _ = try await container.deleteProject(project.id)
                path.removeAll { route in
                    if case .detail = route { return true }
                    return false
                }
            } catch {
                deleteError = "删除失败：\(error.localizedDescription)"
            }
        }
    }
}