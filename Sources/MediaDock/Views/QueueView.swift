import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "Download Queue",
                title: "下载队列",
                subtitle: "任务会按照顺序处理；暂停后可以继续，不需要从头下载。"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            if model.activeJobs.isEmpty {
                EmptyStateCard(
                    symbol: "arrow.down.circle",
                    title: "队列是空的",
                    message: "回到“下载”页面粘贴视频链接，任务会出现在这里。"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.activeJobs) { job in
                            JobCard(job: job)
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

private struct JobCard: View {
    @EnvironmentObject private var model: AppModel
    let job: DownloadJob

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            MediaThumbnail(url: job.video.thumbnailURL, width: 126, height: 71)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.video.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(2)

                    Spacer(minLength: 18)

                    StatusPill(status: job.status)
                }

                HStack(spacing: 7) {
                    Text(job.video.source)
                    Text("·")
                    Text(job.preset.title)
                    Text("·")
                    Text(job.video.durationText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if job.status == .downloading {
                    DownloadProgressBar(
                        progress: job.progress,
                        height: 10,
                        showsIndeterminate: true
                    )

                    HStack(spacing: 12) {
                        Text(progressText(for: job.progress))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.accentColor)

                        if !job.speed.isEmpty {
                            Label(job.speed, systemImage: "speedometer")
                        }
                        if !job.eta.isEmpty {
                            Label(job.eta, systemImage: "timer")
                        }

                        Spacer()

                        Text(job.message)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(job.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

            VStack(spacing: 7) {
                if job.status == .downloading {
                    IconActionButton(symbol: "pause.fill", help: "暂停任务") {
                        model.pause(job.id)
                    }
                } else if job.status == .paused || job.status == .queued {
                    IconActionButton(symbol: "play.fill", help: "继续任务") {
                        model.resume(job.id)
                    }
                }

                IconActionButton(symbol: "xmark", help: "取消任务", role: .destructive) {
                    model.cancel(job.id)
                }
            }
        }
        .cardSurface(padding: 16)
    }

    private func progressText(for progress: Double) -> String {
        if progress > 0 && progress < 0.1 {
            return String(format: "%.1f%%", progress * 100)
        }
        return "\(Int((progress * 100).rounded()))%"
    }
}
