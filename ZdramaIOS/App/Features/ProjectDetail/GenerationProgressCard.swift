import SwiftUI
import ZdramaCore

/// 生成进度卡：阶段名、进度条（出图/出视频按 completed/total 展示）与错误信息。
struct GenerationProgressCard: View {
    let project: DramaProject
    let progress: ProjectProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("生成进度")
                .font(.headline)
            HStack {
                Text(statusText)
                    .font(.subheadline)
                Spacer()
                Text(project.currentStage.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if project.status == .processing, isProgressStage {
                ProgressView(value: progress.fraction)
            }
            if let shotNumber = progress.processingShotNumber, project.status == .processing {
                Text("正在生成第 \(shotNumber) 个镜头…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if case .failed = project.status, let message = project.errorMessage, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var isProgressStage: Bool {
        progress.stage == .image || progress.stage == .video
    }

    private var statusText: String {
        switch project.status {
        case .draft:
            return "尚未开始生成"
        case .processing:
            return progress.displayText
        case .completed:
            return "全部生成完成"
        case .failed:
            return "生成失败"
        case .cancelled:
            return "生成已取消"
        }
    }
}