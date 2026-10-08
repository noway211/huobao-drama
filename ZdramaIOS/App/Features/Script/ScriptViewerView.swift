import SwiftUI
import ZdramaCore

/// 剧本查看页：只读展示剧集脚本内容（无剧集脚本时回退项目脚本），可滚动。
struct ScriptViewerView: View {
    let script: String

    init(episode: Episode?, project: DramaProject?) {
        let episodeScript = episode?.scriptContent?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let episodeScript, !episodeScript.isEmpty {
            self.script = episodeScript
        } else {
            self.script = project?.generatedScript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    var body: some View {
        Group {
            if script.isEmpty {
                ContentUnavailableView(
                    "尚未生成剧本",
                    systemImage: "doc.text",
                    description: Text("请先在详情页点击「剧本」或「全部生成」")
                )
            } else {
                ScrollView {
                    Text(script)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("剧本")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
