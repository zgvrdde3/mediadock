import SwiftUI

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

struct CardSurface: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            }
    }
}

extension View {
    func cardSurface(padding: CGFloat = 20) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor,
                        Color.accentColor.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .shadow(color: Color.accentColor.opacity(configuration.isPressed ? 0.08 : 0.22), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct StatusPill: View {
    let status: DownloadStatus

    private var color: Color {
        switch status {
        case .queued: .secondary
        case .downloading: .accentColor
        case .paused: .orange
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.11), in: Capsule())
    }
}

struct MediaThumbnail: View {
    let url: URL?
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    ZStack {
                        thumbnailBackground

                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else if phase.error != nil {
                            thumbnailPlaceholder
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                    }
                }
            } else {
                ZStack {
                    thumbnailBackground
                    thumbnailPlaceholder
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var thumbnailBackground: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.8),
                Color(red: 0.35, green: 0.22, blue: 0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var thumbnailPlaceholder: some View {
        Image(systemName: "film")
            .font(.system(size: min(width, height) * 0.26, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
    }
}

struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 54, height: 54)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct IconActionButton: View {
    let symbol: String
    let help: String
    let role: ButtonRole?
    let action: () -> Void

    init(symbol: String, help: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct DownloadProgressBar: View {
    let progress: Double
    var height: CGFloat = 8
    var showsIndeterminate: Bool = false

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let width = proxy.size.width
                let fillWidth = clampedProgress > 0
                    ? max(height, width * clampedProgress)
                    : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.075))

                    if clampedProgress > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color(red: 0.31, green: 0.48, blue: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth)
                            .animation(.easeOut(duration: 0.25), value: clampedProgress)
                    } else if showsIndeterminate {
                        let cycle = 1.5
                        let phase = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: cycle) / cycle
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.12),
                                        Color.accentColor.opacity(0.75),
                                        Color.accentColor.opacity(0.12)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(width * 0.34, height * 2))
                            .offset(x: (width * 1.34) * phase - width * 0.34)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("下载进度")
        .accessibilityValue(
            clampedProgress > 0
                ? "\(Int((clampedProgress * 100).rounded()))%"
                : "正在获取进度"
        )
    }
}
