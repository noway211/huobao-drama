import SwiftUI
import ZdramaCore

/// 提示词管理页：创作 / 改写 / 分镜 三个标签页，各自可编辑、保存、恢复默认；
/// 离开有未保存修改的标签页时弹出确认。
@MainActor
struct ManagePromptsView: View {
    private enum PromptTab: Int, CaseIterable, Identifiable {
        case create
        case rewrite
        case storyboard

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .create: return "创作"
            case .rewrite: return "改写"
            case .storyboard: return "分镜"
            }
        }

        var icon: String {
            switch self {
            case .create: return "pencil.and.scribble"
            case .rewrite: return "arrow.triangle.2.circlepath"
            case .storyboard: return "rectangle.3.group"
            }
        }
    }

    @ObservedObject var container: AppContainer

    @State private var selection: PromptTab = .create
    @State private var drafts: [String]
    @State private var saved: [String]
    @State private var confirmLeave = false
    @State private var leavingTab: PromptTab?
    @State private var isReverting = false
    @State private var savedFlash = false
    @State private var saveError: String?

    init(container: AppContainer) {
        self.container = container
        let resolved = Self.resolvedPrompts(container.settingsStore.load())
        _drafts = State(initialValue: resolved)
        _saved = State(initialValue: resolved)
    }

    private static func defaults() -> [String] {
        [
            PromptDefaults.scriptCreatePrompt,
            PromptDefaults.scriptRewritePrompt,
            PromptDefaults.storyboardPrompt
        ]
    }

    private static func resolvedPrompts(_ settings: AgnesSettings) -> [String] {
        [
            PromptResolver.resolve(custom: settings.customScriptCreatePrompt, default: PromptDefaults.scriptCreatePrompt),
            PromptResolver.resolve(custom: settings.customScriptRewritePrompt, default: PromptDefaults.scriptRewritePrompt),
            PromptResolver.resolve(custom: settings.customStoryboardPrompt, default: PromptDefaults.storyboardPrompt)
        ]
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(PromptTab.allCases) { tab in
                editor(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            guard !isReverting else {
                isReverting = false
                return
            }
            guard oldValue != newValue, isDirty(oldValue) else { return }
            leavingTab = oldValue
            confirmLeave = true
        }
        .confirmationDialog(
            "当前提示词已修改",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("放弃修改", role: .destructive) {
                if let tab = leavingTab {
                    drafts[tab.rawValue] = saved[tab.rawValue]
                }
                leavingTab = nil
            }
            Button("继续编辑", role: .cancel) {
                if let tab = leavingTab {
                    isReverting = true
                    selection = tab
                }
                leavingTab = nil
            }
        } message: {
            Text("离开当前标签页将丢失尚未保存的修改")
        }
        .navigationTitle("提示词")
    }

    private func editor(for tab: PromptTab) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: draftBinding(tab))
                .autocorrectionDisabled()
                .padding(8)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if drafts[tab.rawValue].isEmpty {
                        Text("请输入\(tab.title)提示词")
                            .foregroundStyle(.tertiary)
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Text(savedFlash ? "已保存" : " ")
                    .font(.footnote)
                    .foregroundStyle(.green)
                Spacer()
                Button("恢复默认") {
                    drafts[tab.rawValue] = Self.defaults()[tab.rawValue]
                }
                Button("保存") { save(tab) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func draftBinding(_ tab: PromptTab) -> Binding<String> {
        Binding(
            get: { drafts[tab.rawValue] },
            set: { drafts[tab.rawValue] = $0 }
        )
    }

    private func isDirty(_ tab: PromptTab) -> Bool {
        drafts[tab.rawValue] != saved[tab.rawValue]
    }

    private func save(_ tab: PromptTab) {
        var settings = container.settingsStore.load()
        let value = drafts[tab.rawValue].trimmingCharacters(in: .whitespacesAndNewlines)
        switch tab {
        case .create:
            settings.customScriptCreatePrompt = value
        case .rewrite:
            settings.customScriptRewritePrompt = value
        case .storyboard:
            settings.customStoryboardPrompt = value
        }
        do {
            try container.settingsStore.save(settings)
            saveError = nil
            saved = Self.resolvedPrompts(container.settingsStore.load())
            // 清空保存等价于恢复默认：回填解析后的文案，避免保存后仍被判定为"已修改"
            drafts[tab.rawValue] = saved[tab.rawValue]
            savedFlash = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                savedFlash = false
            }
        } catch {
            savedFlash = false
            saveError = "保存失败：\(error.localizedDescription)"
        }
    }
}
