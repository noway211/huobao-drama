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
    @State private var deleteError: String?

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
            do {
                _ = try await container.deleteProject(project.id)
                reload()
            } catch {
                // 失败时保留列表原状，仅弹出错误提示（不 reload，避免覆盖错误文案）
                deleteError = "删除失败：\(error.localizedDescription)"
            }
        }
    }

    private static func dateText(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}
