import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                PageHeader(
                    eyebrow: "Library",
                    title: "下载历史",
                    subtitle: "查找已完成、失败或取消过的下载任务。"
                )

                Spacer()

                if !model.historyJobs.isEmpty {
                    Button("清除记录", role: .destructive) {
                        model.clearHistory()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("只清除记录，不会删除视频文件")
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            if model.historyJobs.isEmpty {
                EmptyStateCard(
                    symbol: "clock.arrow.circlepath",
                    title: "还没有下载记录",
                    message: "完成或失败的任务会保存在这里，退出 App 后也不会丢失。"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.historyJobs) { job in
                            HistoryRow(job: job)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1_060)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var model: AppModel
    let job: DownloadJob

    private var statusIcon: String {
        switch job.status {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        default: "circle"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        default: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            MediaThumbnail(url: job.video.thumbnailURL, width: 82, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(job.video.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(job.message)
                        .lineLimit(1)
                    Text("·")
                    Text(job.preset.title)
                    if let completedAt = job.completedAt {
                        Text("·")
                        Text(completedAt, format: .dateTime.month().day().hour().minute())
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                if let outputURL = job.outputURL, job.status == .completed {
                    IconActionButton(symbol: "play.fill", help: "打开文件") {
                        model.openFile(outputURL)
                    }
                    IconActionButton(symbol: "folder", help: "在 Finder 中显示") {
                        model.revealFile(outputURL)
                    }
                }

                if job.status == .failed || job.status == .cancelled {
                    IconActionButton(symbol: "arrow.clockwise", help: "重新下载") {
                        model.retry(job.id)
                        withAnimation {
                            model.selectedSection = .queue
                        }
                    }
                }

                IconActionButton(symbol: "trash", help: "仅删除这条记录", role: .destructive) {
                    model.remove(job.id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 1)
        }
    }
}
