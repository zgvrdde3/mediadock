import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 210)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
                .ignoresSafeArea()

            Group {
                switch model.selectedSection {
                case .downloads:
                    DownloadsView()
                case .queue:
                    QueueView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color.accentColor.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                BrandMark(size: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MediaDock")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("视频下载工具")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 48)
            .padding(.horizontal, 16)

            VStack(spacing: 5) {
                ForEach(SidebarSection.allCases) { section in
                    SidebarButton(
                        section: section,
                        isSelected: model.selectedSection == section,
                        badge: section == .queue ? model.activeCount : 0
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.selectedSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 20)

            CoreMiniStatus()
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }
}

private struct SidebarButton: View {
    let section: SidebarSection
    let isSelected: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)

                Text(section.title)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CoreMiniStatus: View {
    @EnvironmentObject private var model: AppModel

    private var ready: Bool {
        model.coreStatus.isReady
    }

    var body: some View {
        Button {
            model.selectedSection = .settings
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(ready ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: (ready ? Color.green : Color.orange).opacity(0.4), radius: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ready ? "下载核心已就绪" : "下载核心未就绪")
                        .font(.caption.weight(.medium))
                    Text(ready ? "yt-dlp 可用" : "点击查看详情")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.48, blue: 1.0),
                            Color(red: 0.38, green: 0.25, blue: 0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.accentColor.opacity(0.22), radius: size * 0.18, y: size * 0.08)

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.025)
        }
        .frame(width: size, height: size)
    }
}
