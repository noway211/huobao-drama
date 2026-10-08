import SwiftUI
import ZdramaCore

/// 项目列表页：按 updatedAt 降序展示，支持滑动删除（带确认）与进入详情。
@MainActor
struct ProjectListView: View {
    @ObservedObject var container: AppContainer
    @Binding var path: [AppRoute]

    @State private var projects: [DramaProject] = []
    @State private var loadError: String?
    @State private var pendingDelete: DramaProject?

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
            } else if projects.isEmpty {
                ContentUnavailableView(
                    "暂无项目",
                    systemImage: "film.stack",
                    description: Text("点击首页「新建」开始创作你的第一部短剧")
                )
            } else {
                List {
                    ForEach(projects) { project in
                        row(project)
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) {
                                    pendingDelete = project
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("项目")
        .onAppear(perform: reload)
        .confirmationDialog(
            "删除项目",
            isPresented: deleteDialogPresented,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { project in
            Button("删除", role: .destructive) { delete(project) }
            Button("取消", role: .cancel) {}
        } message: { project in
            Text("将删除「\(project.title)」及其全部数据，此操作不可恢复。")
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func row(_ project: DramaProject) -> some View {
        Button {
            path.append(.detail(project.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(project.style)
                    Text(project.status.displayName)
                    Spacer()
                    Text(Self.dateText(project.updatedAt))
                        .font(.footnote)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reload() {
        do {
            projects = try container.loadProjects()
            loadError = nil
        } catch {
            loadError = "加载项目失败：\(error.localizedDescription)"
        }
    }

    private func delete(_ project: DramaProject) {
        Task {
            defer { reload() }
            do {
                _ = try await container.deleteProject(project.id)
            } catch {
                loadError = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    private static func dateText(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}

private extension ProjectStatus {
    var displayName: String {
        switch self {
        case .draft: return "草稿"
        case .processing: return "生成中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}