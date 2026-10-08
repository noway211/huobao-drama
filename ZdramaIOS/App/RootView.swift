import SwiftUI

/// 应用内导航路由。
enum AppRoute: Hashable {
    case settings
    case create
    case projects
    case detail(Int64)
}

struct RootView: View {
    @ObservedObject var container: AppContainer
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView(container: container)
                    case .create:
                        CreateProjectView(container: container, path: $path)
                    case .projects:
                        ProjectListView(container: container, path: $path)
                    case .detail(let id):
                        Text("detail \(id)")
                            .navigationTitle("详情")
                    }
                }
        }
    }
}
