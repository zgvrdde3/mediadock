import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case downloads
    case queue
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "下载"
        case .queue: "队列"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .queue: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum DownloadPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case best
    case fullHD
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: "最佳画质"
        case .fullHD: "1080p"
        case .audio: "仅音频"
        }
    }

    var subtitle: String {
        switch self {
        case .best: "自动选择最高质量"
        case .fullHD: "体积与清晰度均衡"
        case .audio: "导出为 M4A 音频"
        }
    }

    var symbol: String {
        switch self {
        case .best: "sparkles"
        case .fullHD: "rectangle.inset.filled"
        case .audio: "waveform"
        }
    }
}

enum DownloadStatus: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled

    var title: String {
        switch self {
        case .queued: "等待中"
        case .downloading: "下载中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    var isActive: Bool {
        self == .downloading
    }

    var isHistory: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

enum BrowserCookieSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case chrome
    case safari
    case edge
    case firefox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "关闭"
        case .chrome: "Chrome"
        case .safari: "Safari"
        case .edge: "Edge"
        case .firefox: "Firefox"
        }
    }

    var ytDlpName: String? {
        self == .off ? nil : rawValue
    }

    static var supportedLoginSources: [BrowserCookieSource] {
        [.off, .chrome, .edge]
    }
}

struct VideoInfo: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let source: String
    let webpageURL: URL
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let qualities: [Int]
    let isLive: Bool

    var durationText: String {
        guard let duration, duration.isFinite, duration > 0 else {
            return isLive ? "直播内容" : "时长未知"
        }

        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var qualityText: String {
        guard !qualities.isEmpty else { return "自动" }
        return qualities.prefix(4).map { "\($0)p" }.joined(separator: " · ")
    }
}

enum BatchParseState: Sendable, Equatable {
    case pending
    case parsing
    case ready
    case failed
    case duplicate

    var isFinished: Bool {
        switch self {
        case .pending, .parsing:
            false
        case .ready, .failed, .duplicate:
            true
        }
    }
}

enum LinkInputMode: Sendable, Hashable {
    case single
    case batch
}

struct BatchLinkItem: Identifiable, Sendable {
    let id: UUID
    let url: URL
    var state: BatchParseState
    var video: VideoInfo?
    var errorMessage: String?

    init(url: URL) {
        id = UUID()
        self.url = url
        state = .pending
        video = nil
        errorMessage = nil
    }
}

func extractVideoLinks(from text: String) -> [URL] {
    guard let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    ) else {
        return []
    }

    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
    var seen = Set<String>()

    return detector.matches(in: text, options: [], range: fullRange).compactMap { match in
        guard let candidate = match.url,
              let scheme = candidate.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              candidate.host != nil else {
            return nil
        }

        var components = URLComponents(
            url: candidate,
            resolvingAgainstBaseURL: false
        )
        components?.scheme = scheme
        components?.host = candidate.host?.lowercased()
        components?.fragment = nil
        guard let normalized = components?.url else { return nil }

        let key = normalized.absoluteString
        guard seen.insert(key).inserted else { return nil }
        return normalized
    }
}

struct DownloadJob: Codable, Identifiable, Sendable {
    let id: UUID
    let video: VideoInfo
    let preset: DownloadPreset
    let destinationDirectory: URL
    let createdAt: Date

    var status: DownloadStatus
    var progress: Double
    var speed: String
    var eta: String
    var message: String
    var outputURL: URL?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        video: VideoInfo,
        preset: DownloadPreset,
        destinationDirectory: URL,
        createdAt: Date = Date(),
        status: DownloadStatus = .queued,
        progress: Double = 0,
        speed: String = "",
        eta: String = "",
        message: String = "准备下载",
        outputURL: URL? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.video = video
        self.preset = preset
        self.destinationDirectory = destinationDirectory
        self.createdAt = createdAt
        self.status = status
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.message = message
        self.outputURL = outputURL
        self.completedAt = completedAt
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var downloadDirectory: URL
    var defaultPreset: DownloadPreset
    var maxConcurrentDownloads: Int
    var openFolderOnCompletion: Bool
    var playSoundOnCompletion: Bool
    var cookieSource: BrowserCookieSource?
    var browserProfileDirectoryPath: String?
    var browserProfileImportedAt: Date?
    var browserProfileSourceBookmark: Data? = nil
    var multiConnectionDownload: Bool? = true
    var downloadConnectionCount: Int? = 8

    var usesMultiConnectionDownload: Bool {
        get { multiConnectionDownload ?? true }
        set { multiConnectionDownload = newValue }
    }

    var downloadConnections: Int {
        get { min(max(downloadConnectionCount ?? 8, 2), 16) }
        set { downloadConnectionCount = min(max(newValue, 2), 16) }
    }

    static var defaults: AppSettings {
        let movies = FileManager.default.urls(
            for: .moviesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        return AppSettings(
            downloadDirectory: movies.appendingPathComponent("MediaDock", isDirectory: true),
            defaultPreset: .best,
            maxConcurrentDownloads: 1,
            openFolderOnCompletion: false,
            playSoundOnCompletion: true,
            multiConnectionDownload: true,
            downloadConnectionCount: 8
        )
    }
}

struct PersistedState: Codable {
    var settings: AppSettings
    var jobs: [DownloadJob]
}

struct CoreStatus: Sendable {
    var ytDlpVersion: String?
    var ffmpegVersion: String?
    var javaScriptVersion: String?
    var aria2Version: String?
    var ytDlpPath: String?
    var ffmpegPath: String?
    var javaScriptPath: String?
    var aria2Path: String?
    var errorMessage: String?

    var isReady: Bool {
        ytDlpPath != nil
    }

    var canMerge: Bool {
        ffmpegPath != nil
    }

    var canDownloadWithMultipleConnections: Bool {
        aria2Path != nil
    }

    static let checking = CoreStatus(
        ytDlpVersion: nil,
        ffmpegVersion: nil,
        javaScriptVersion: nil,
        aria2Version: nil,
        ytDlpPath: nil,
        ffmpegPath: nil,
        javaScriptPath: nil,
        aria2Path: nil,
        errorMessage: nil
    )
}
