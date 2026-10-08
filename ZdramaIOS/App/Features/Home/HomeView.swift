import SwiftUI

/// 首页：设置 / 新建 / 项目 三个入口。
struct HomeView: View {
    @Binding var path: [AppRoute]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("火宝短剧")
                .font(.system(size: 36, weight: .bold))
            Text("AI 驱动的短剧创作工具")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
            VStack(spacing: 14) {
                entryButton("设置", systemImage: "gearshape.fill", tint: .gray) {
                    path.append(.settings)
                }
                entryButton("新建", systemImage: "plus.circle.fill", tint: .blue) {
                    path.append(.create)
                }
                entryButton("项目", systemImage: "film.stack.fill", tint: .orange) {
                    path.append(.projects)
                }
            }
            .padding(.horizontal, 40)
            Spacer().frame(height: 60)
        }
        .navigationTitle("首页")
    }

    private func entryButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}
