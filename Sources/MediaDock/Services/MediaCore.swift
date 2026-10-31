import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String

    var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum MediaCoreError: LocalizedError {
    case missingYTDLP
    case missingFFmpeg
    case invalidLink
    case invalidResponse(String)
    case executionFailed(Int32, String)

    var requiresAuthentication: Bool {
        guard case .executionFailed(_, let output) = self else { return false }
        let text = output.lowercased()
        return text.contains("sign in to confirm")
            || text.contains("not a bot")
            || text.contains("login required")
            || text.contains("cookies")
            || text.contains("private video")
            || text.contains("age-restricted")
    }

    var isTransientYouTubePlayerFailure: Bool {
        guard case .executionFailed(_, let output) = self else { return false }
        let text = output.lowercased()
        return text.contains("page needs to be reloaded")
            || text.contains("forcing sabr streaming")
            || text.contains("n challenge solving failed")
    }

    var errorDescription: String? {
        switch self {
        case .missingYTDLP:
            return "找不到下载核心 yt-dlp"
        case .missingFFmpeg:
            return "缺少用于合并音视频的 ffmpeg"
        case .invalidLink:
            return "请输入有效的 http 或 https 视频链接"
        case .invalidResponse(let detail):
            return "无法读取视频信息：\(detail)"
        case .executionFailed(let status, let output):
            let detail = Self.friendlyMessage(from: output)
            return detail.isEmpty ? "下载核心运行失败（状态码 \(status)）" : detail
        }
    }

    static func friendlyMessage(from output: String) -> String {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if text.localizedCaseInsensitiveContains("unsupported url") {
            return "这个链接暂不受支持"
        }
        if text.localizedCaseInsensitiveContains("private video")
            || text.localizedCaseInsensitiveContains("login required") {
            return "该视频需要登录后才能访问"
        }
        if text.localizedCaseInsensitiveContains("sign in to confirm")
            || text.localizedCaseInsensitiveContains("not a bot") {
            return "视频源要求登录或人机验证；MediaDock 不会自动绕过该限制"
        }
        if text.localizedCaseInsensitiveContains("could not find chrome cookies database")
            || text.localizedCaseInsensitiveContains("could not find firefox cookies database")
            || text.localizedCaseInsensitiveContains("could not find safari cookies database")
            || text.localizedCaseInsensitiveContains("cannot decrypt cookies")
            || text.localizedCaseInsensitiveContains("operation not permitted") {
            return "无法读取浏览器登录状态。请在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中允许 MediaDock，然后重新打开 App"
        }
        if text.localizedCaseInsensitiveContains("requested format is not available") {
            return "这个视频没有匹配的下载格式，请更换画质或稍后重试"
        }
        if text.localizedCaseInsensitiveContains("page needs to be reloaded")
            || text.localizedCaseInsensitiveContains("forcing sabr streaming")
            || text.localizedCaseInsensitiveContains("n challenge solving failed") {
            return "YouTube 页面数据未完整加载，已自动重试；仍失败请再点重试或切换网络节点"
        }
        if text.localizedCaseInsensitiveContains("drm") {
            return "该内容受版权保护，MediaDock 不会绕过 DRM"
        }
        if text.localizedCaseInsensitiveContains("video unavailable") {
            return "视频不可用或已被删除"
        }
        if text.localizedCaseInsensitiveContains("timed out")
            || text.localizedCaseInsensitiveContains("network is unreachable")
            || text.localizedCaseInsensitiveContains("connection") {
            return "网络连接失败，请检查网络后重试"
        }

        let usefulLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return usefulLines.suffix(2).joined(separator: " ")
    }
}

enum YouTubePlayerClient: String, Sendable {
    case webEmbedded = "web_embedded"
    case web
}

final class ProcessRunner: @unchecked Sendable {
    func run(
        executable: URL,
        arguments: [String],
        standardInput: Data? = nil,
        onStandardOutputLine: (@Sendable (String) -> Void)? = nil,
        onStandardErrorLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let collector = OutputCollector(
            outputHandler: onStandardOutputLine,
            errorHandler: onStandardErrorLine
        )

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = standardInput.map { data in
            let pipe = Pipe()
            pipe.fileHandleForWriting.write(data)
            try? pipe.fileHandleForWriting.close()
            return pipe
        } ?? FileHandle.nullDevice

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.receive(handle.availableData, stream: .standardOutput)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.receive(handle.availableData, stream: .standardError)
        }

        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { finishedProcess in
                        continuation.resume(returning: finishedProcess.terminationStatus)
                    }

                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            collector.finish()
            throw error
        }

        try? await Task.sleep(for: .milliseconds(80))
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        collector.finish()

        if Task.isCancelled {
            throw CancellationError()
        }

        return collector.result(status: status)
    }
}

private final class OutputCollector: @unchecked Sendable {
    enum Stream {
        case standardOutput
        case standardError
    }

    private let lock = NSLock()
    private let outputHandler: (@Sendable (String) -> Void)?
    private let errorHandler: (@Sendable (String) -> Void)?
    private var outputBuffer = ""
    private var errorBuffer = ""
    private var outputData = Data()
    private var errorData = Data()

    init(
        outputHandler: (@Sendable (String) -> Void)?,
        errorHandler: (@Sendable (String) -> Void)?
    ) {
        self.outputHandler = outputHandler
        self.errorHandler = errorHandler
    }

    func receive(_ data: Data, stream: Stream) {
        guard !data.isEmpty else { return }

        var lines: [String] = []
        lock.lock()

        switch stream {
        case .standardOutput:
            outputData.append(data)
            outputBuffer.append(String(decoding: data, as: UTF8.self))
            lines = takeCompleteLines(from: &outputBuffer)
        case .standardError:
            errorData.append(data)
            errorBuffer.append(String(decoding: data, as: UTF8.self))
            lines = takeCompleteLines(from: &errorBuffer)
        }

        lock.unlock()

        let handler = stream == .standardOutput ? outputHandler : errorHandler
        for line in lines {
            handler?(line)
        }
    }

    func finish() {
        var outputLines: [String] = []
        var errorLines: [String] = []

        lock.lock()
        if !outputBuffer.isEmpty {
            outputLines = [outputBuffer]
            outputBuffer = ""
        }
        if !errorBuffer.isEmpty {
            errorLines = [errorBuffer]
            errorBuffer = ""
        }
        lock.unlock()

        outputLines.forEach { outputHandler?($0) }
        errorLines.forEach { errorHandler?($0) }
    }

    func result(status: Int32) -> ProcessResult {
        lock.lock()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)
        lock.unlock()
        return ProcessResult(status: status, standardOutput: output, standardError: error)
    }

    private func takeCompleteLines(from buffer: inout String) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .newlines)
            lines.append(line)
            buffer = String(buffer[buffer.index(after: newline)...])
        }
        return lines
    }
}

enum MediaCoreLocator {
    static func ytDlpURL() -> URL? {
        locate(named: "yt-dlp")
    }

    static func ffmpegURL() -> URL? {
        locate(named: "ffmpeg")
    }

    static func javaScriptRuntimeURL() -> URL? {
        locate(named: "node")
    }

    static func aria2cURL() -> URL? {
        locate(named: "aria2c")
    }

    private static func locate(named name: String) -> URL? {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["MEDIADOCK_CORE_DIR"] {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(name))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("MediaCore/\(name)"))
        }

        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/\(name)")
        )

        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let conventionalDirectories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CherryStudio/Toolchain/mise/shims")
                .path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ]

        for directory in pathDirectories + conventionalDirectories {
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name))
        }

        var visited = Set<String>()
        return candidates.first { candidate in
            let path = candidate.standardizedFileURL.path
            guard visited.insert(path).inserted else { return false }
            return FileManager.default.isExecutableFile(atPath: path)
        }?.standardizedFileURL
    }
}

struct ProgressUpdate: Sendable {
    let fraction: Double
    let speed: String
    let eta: String
}

struct DownloadEngineOptions: Sendable {
    let usesMultiConnection: Bool
    let connectionCount: Int

    static let native = DownloadEngineOptions(
        usesMultiConnection: false,
        connectionCount: 1
    )
}

private struct DownloadFormat: Sendable {
    let id: String
    let protocolName: String
    let ext: String
    let vcodec: String
    let acodec: String
    let height: Int?
    let tbr: Double?
    let fileSize: Int64?

    init?(_ source: YtDlpFormat) {
        guard let id = source.formatID,
              !id.isEmpty,
              let protocolName = source.protocolName,
              !protocolName.isEmpty,
              protocolName.lowercased() != "mhtml",
              let ext = source.ext,
              !ext.isEmpty else {
            return nil
        }

        self.id = id
        self.protocolName = protocolName
        self.ext = ext
        self.vcodec = source.vcodec ?? "none"
        self.acodec = source.acodec ?? "none"
        self.height = source.height
        self.tbr = source.tbr
        self.fileSize = source.fileSize ?? source.fileSizeApprox
    }

    var hasVideo: Bool {
        vcodec != "none"
    }

    var hasAudio: Bool {
        acodec != "none"
    }

    var isFragmented: Bool {
        let protocolName = protocolName.lowercased()
        return protocolName.contains("m3u8")
            || protocolName.contains("dash")
    }
}

private enum DownloadPlan: Sendable {
    case single(DownloadFormat)
    case parallel(video: DownloadFormat, audio: DownloadFormat)
}

private struct Aria2RPCConfiguration: Sendable {
    let port: Int
    let secret: String
}

private struct Aria2RPCResult: Decodable {
    let completedLength: String
    let totalLength: String
    let downloadSpeed: String
    let connections: String?
    let status: String?
}

private struct Aria2RPCResponse<Result: Decodable>: Decodable {
    let result: Result?
}

private actor ParallelDownloadProgressReporter {
    enum Track: Hashable {
        case video
        case audio
    }

    private let videoWeight: Double
    private let audioWeight: Double
    private let totalBytes: Int64
    private let onProgress: @Sendable (ProgressUpdate) -> Void
    private var fractions: [Track: Double] = [:]
    private var speeds: [Track: Double] = [:]

    init(
        videoWeight: Double,
        audioWeight: Double,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (ProgressUpdate) -> Void
    ) {
        self.videoWeight = max(videoWeight, 1)
        self.audioWeight = max(audioWeight, 1)
        self.totalBytes = totalBytes
        self.onProgress = onProgress
    }

    func update(_ track: Track, update: ProgressUpdate) {
        fractions[track] = min(max(update.fraction, 0), 1)
        speeds[track] = transferRateBytesPerSecond(update.speed)

        let totalWeight = videoWeight + audioWeight
        let fraction = (
            (fractions[.video] ?? 0) * videoWeight
                + (fractions[.audio] ?? 0) * audioWeight
        ) / totalWeight
        let speed = (speeds[.video] ?? 0) + (speeds[.audio] ?? 0)
        let remainingBytes = Double(totalBytes) * max(1 - fraction, 0)
        let eta = totalBytes > 0 && speed > 0
            ? etaText(remainingBytes / speed)
            : ""

        onProgress(
            ProgressUpdate(
                fraction: fraction,
                speed: transferRateText(speed),
                eta: eta
            )
        )
    }
}

struct YtDlpService: Sendable {
    private let runner = ProcessRunner()

    func checkCore() async -> CoreStatus {
        async let ytDlp = version(
            executable: MediaCoreLocator.ytDlpURL(),
            arguments: ["--version"]
        )
        async let ffmpeg = version(
            executable: MediaCoreLocator.ffmpegURL(),
            arguments: ["-version"]
        )
        async let javaScript = version(
            executable: MediaCoreLocator.javaScriptRuntimeURL(),
            arguments: ["--version"]
        )
        async let aria2 = version(
            executable: MediaCoreLocator.aria2cURL(),
            arguments: ["--version"]
        )

        let (ytDlpResult, ffmpegResult, javaScriptResult, aria2Result) =
            await (ytDlp, ffmpeg, javaScript, aria2)
        let ytDlpPath = MediaCoreLocator.ytDlpURL()?.path
        let ffmpegPath = MediaCoreLocator.ffmpegURL()?.path
        let javaScriptPath = MediaCoreLocator.javaScriptRuntimeURL()?.path
        let aria2Path = MediaCoreLocator.aria2cURL()?.path

        return CoreStatus(
            ytDlpVersion: ytDlpResult,
            ffmpegVersion: ffmpegResult,
            javaScriptVersion: javaScriptResult,
            aria2Version: aria2Result,
            ytDlpPath: ytDlpPath,
            ffmpegPath: ffmpegPath,
            javaScriptPath: javaScriptPath,
            aria2Path: aria2Path,
            errorMessage: ytDlpPath == nil ? MediaCoreError.missingYTDLP.localizedDescription : nil
        )
    }

    func parse(
        url: URL,
        cookieSource: BrowserCookieSource? = nil,
        cookieProfileDirectory: URL? = nil,
        playerClient: YouTubePlayerClient? = nil
    ) async throws -> VideoInfo {
        guard let executable = MediaCoreLocator.ytDlpURL() else {
            throw MediaCoreError.missingYTDLP
        }

        var arguments = [
            "--ignore-config",
            "--dump-single-json",
            "--skip-download",
            "--no-playlist",
            "--no-warnings",
            "--no-color"
        ]
        arguments.append(contentsOf: cookieArguments(
            for: cookieSource,
            profileDirectory: cookieProfileDirectory
        ))
        arguments.append(contentsOf: javaScriptRuntimeArguments())
        arguments.append(contentsOf: youtubePlayerArguments(
            for: url,
            playerClient: playerClient
        ))
        arguments.append(url.absoluteString)

        let result = try await runner.run(
            executable: executable,
            arguments: arguments
        )

        guard result.status == 0 else {
            throw MediaCoreError.executionFailed(result.status, result.combinedOutput)
        }

        if let metadata = try? JSONDecoder().decode(YtDlpMetadata.self, from: Data(result.standardOutput.utf8)) {
            let pageURL = [metadata.webpageURL, metadata.originalURL]
                .compactMap { $0 }
                .compactMap(URL.init(string:))
                .first ?? url
            let heights = (metadata.formats ?? [])
                .filter { ($0.vcodec ?? "none") != "none" }
                .compactMap(\.height)
                .filter { $0 > 0 }
            let qualities = Array(Set(heights)).sorted(by: >)

            return VideoInfo(
                id: metadata.id ?? UUID().uuidString,
                title: metadata.title ?? "未命名视频",
                source: metadata.extractorKey ?? metadata.extractor ?? pageURL.host ?? "视频站点",
                webpageURL: pageURL,
                thumbnailURL: metadata.thumbnail.flatMap(URL.init(string:)),
                duration: metadata.duration,
                qualities: qualities,
                isLive: metadata.isLive ?? false
            )
        }

        let detail = MediaCoreError.friendlyMessage(from: result.combinedOutput)
        throw MediaCoreError.invalidResponse(detail.isEmpty ? "返回格式不正确" : detail)
    }

    func download(
        job: DownloadJob,
        cookieSource: BrowserCookieSource? = nil,
        cookieProfileDirectory: URL? = nil,
        playerClient: YouTubePlayerClient? = nil,
        engineOptions: DownloadEngineOptions = .native,
        onProgress: @escaping @Sendable (ProgressUpdate) -> Void,
        onMessage: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        guard let executable = MediaCoreLocator.ytDlpURL() else {
            throw MediaCoreError.missingYTDLP
        }

        try FileManager.default.createDirectory(
            at: job.destinationDirectory,
            withIntermediateDirectories: true
        )

        let plan = try await resolveDownloadPlan(
            job: job,
            cookieSource: cookieSource,
            cookieProfileDirectory: cookieProfileDirectory,
            playerClient: playerClient
        )

        switch plan {
        case .single(let format):
            let result = try await executeFormatDownload(
                executable: executable,
                job: job,
                format: format,
                destinationDirectory: job.destinationDirectory,
                outputTemplate: "%(title).150B [%(id)s].%(ext)s",
                cookieSource: cookieSource,
                cookieProfileDirectory: cookieProfileDirectory,
                playerClient: playerClient,
                engineOptions: engineOptions,
                onProgress: onProgress,
                onMessage: onMessage
            )
            return try downloadedFile(from: result, in: job.destinationDirectory)

        case .parallel(let videoFormat, let audioFormat):
            onMessage("正在并行下载视频与音频")
            let workDirectory = parallelWorkDirectory(for: job)
            try FileManager.default.createDirectory(
                at: workDirectory,
                withIntermediateDirectories: true
            )
            let reporter = ParallelDownloadProgressReporter(
                videoWeight: Double(videoFormat.fileSize ?? 6_000_000),
                audioWeight: Double(audioFormat.fileSize ?? 1_000_000),
                totalBytes: [videoFormat.fileSize, audioFormat.fileSize]
                    .compactMap { $0 }
                    .reduce(0, +),
                onProgress: onProgress
            )

            async let videoResult = executeFormatDownload(
                executable: executable,
                job: job,
                format: videoFormat,
                destinationDirectory: workDirectory,
                outputTemplate: "video.%(ext)s",
                cookieSource: cookieSource,
                cookieProfileDirectory: cookieProfileDirectory,
                playerClient: playerClient,
                engineOptions: engineOptions,
                onProgress: { update in
                    Task {
                        await reporter.update(.video, update: update)
                    }
                },
                onMessage: onMessage
            )
            async let audioResult = executeFormatDownload(
                executable: executable,
                job: job,
                format: audioFormat,
                destinationDirectory: workDirectory,
                outputTemplate: "audio.%(ext)s",
                cookieSource: cookieSource,
                cookieProfileDirectory: cookieProfileDirectory,
                playerClient: playerClient,
                engineOptions: engineOptions,
                onProgress: { update in
                    Task {
                        await reporter.update(.audio, update: update)
                    }
                },
                onMessage: onMessage
            )

            let (videoProcess, audioProcess) = try await (videoResult, audioResult)
            let videoURL = try downloadedFile(from: videoProcess, in: workDirectory)
            let audioURL = try downloadedFile(from: audioProcess, in: workDirectory)

            try Task.checkCancellation()
            onMessage("正在合并音视频")
            onProgress(ProgressUpdate(fraction: 1, speed: "", eta: ""))
            let output = try await mergeDownloadedStreams(
                videoURL: videoURL,
                audioURL: audioURL,
                videoFormat: videoFormat,
                audioFormat: audioFormat,
                job: job,
                workDirectory: workDirectory
            )
            try? FileManager.default.removeItem(at: workDirectory)
            return output
        }
    }

    private func resolveDownloadPlan(
        job: DownloadJob,
        cookieSource: BrowserCookieSource?,
        cookieProfileDirectory: URL?,
        playerClient: YouTubePlayerClient?
    ) async throws -> DownloadPlan {
        guard let executable = MediaCoreLocator.ytDlpURL() else {
            throw MediaCoreError.missingYTDLP
        }

        var arguments = [
            "--ignore-config",
            "--dump-single-json",
            "--skip-download",
            "--no-playlist",
            "--no-warnings",
            "--no-color"
        ]
        arguments.append(contentsOf: cookieArguments(
            for: cookieSource,
            profileDirectory: cookieProfileDirectory
        ))
        arguments.append(contentsOf: javaScriptRuntimeArguments())
        arguments.append(contentsOf: youtubePlayerArguments(
            for: job.video.webpageURL,
            playerClient: playerClient
        ))
        arguments.append(job.video.webpageURL.absoluteString)

        let result = try await runner.run(
            executable: executable,
            arguments: arguments
        )
        guard result.status == 0 else {
            throw MediaCoreError.executionFailed(result.status, result.combinedOutput)
        }
        guard let metadata = try? JSONDecoder().decode(
            YtDlpMetadata.self,
            from: Data(result.standardOutput.utf8)
        ), let formats = metadata.formats else {
            throw MediaCoreError.invalidResponse("无法读取可用下载格式")
        }

        let candidates = formats.compactMap(DownloadFormat.init)
        return try downloadPlan(
            for: job.preset,
            formats: candidates
        )
    }

    private func downloadPlan(
        for preset: DownloadPreset,
        formats: [DownloadFormat]
    ) throws -> DownloadPlan {
        let audioFormats = formats
            .filter { $0.hasAudio && !$0.hasVideo }
            .sorted(by: isBetterAudioFormat)
        let combinedFormats = formats
            .filter { $0.hasVideo && $0.hasAudio }
            .sorted(by: isBetterVideoFormat)
        let videoFormats = formats
            .filter { $0.hasVideo && !$0.hasAudio }
            .sorted(by: isBetterVideoFormat)

        if preset == .audio {
            if let audio = audioFormats.first ?? combinedFormats.first {
                return .single(audio)
            }
            throw MediaCoreError.invalidResponse("没有可用的音频格式")
        }

        let maximumHeight = preset == .fullHD ? 1080 : Int.max
        let combined = combinedFormats.first {
            ($0.height ?? 0) <= maximumHeight
        }
        let video = videoFormats.first {
            ($0.height ?? 0) <= maximumHeight
        }
        let audio = audioFormats.first

        if let video, let audio, shouldUseParallelStreams(video, insteadOf: combined) {
            return .parallel(video: video, audio: audio)
        }
        if let combined {
            return .single(combined)
        }
        if let video, let audio {
            return .parallel(video: video, audio: audio)
        }
        if let fallback = formats.first {
            return .single(fallback)
        }
        throw MediaCoreError.invalidResponse("这个视频没有可用的下载格式")
    }

    private func shouldUseParallelStreams(
        _ video: DownloadFormat,
        insteadOf combined: DownloadFormat?
    ) -> Bool {
        guard let combined else { return true }
        let videoHeight = video.height ?? 0
        let combinedHeight = combined.height ?? 0
        if videoHeight != combinedHeight {
            return videoHeight > combinedHeight
        }
        return (video.tbr ?? 0) > (combined.tbr ?? 0) * 1.08
    }

    private func isBetterVideoFormat(
        _ lhs: DownloadFormat,
        _ rhs: DownloadFormat
    ) -> Bool {
        if (lhs.height ?? 0) != (rhs.height ?? 0) {
            return (lhs.height ?? 0) > (rhs.height ?? 0)
        }
        if (lhs.tbr ?? 0) != (rhs.tbr ?? 0) {
            return (lhs.tbr ?? 0) > (rhs.tbr ?? 0)
        }
        return preferredContainerRank(lhs.ext) < preferredContainerRank(rhs.ext)
    }

    private func isBetterAudioFormat(
        _ lhs: DownloadFormat,
        _ rhs: DownloadFormat
    ) -> Bool {
        if (lhs.tbr ?? 0) != (rhs.tbr ?? 0) {
            return (lhs.tbr ?? 0) > (rhs.tbr ?? 0)
        }
        return preferredContainerRank(lhs.ext) < preferredContainerRank(rhs.ext)
    }

    private func preferredContainerRank(_ ext: String) -> Int {
        switch ext.lowercased() {
        case "mp4", "m4a": 0
        case "webm": 1
        default: 2
        }
    }

    private func executeFormatDownload(
        executable: URL,
        job: DownloadJob,
        format: DownloadFormat,
        destinationDirectory: URL,
        outputTemplate: String,
        cookieSource: BrowserCookieSource?,
        cookieProfileDirectory: URL?,
        playerClient: YouTubePlayerClient?,
        engineOptions: DownloadEngineOptions,
        onProgress: @escaping @Sendable (ProgressUpdate) -> Void,
        onMessage: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        var arguments = [
            "--ignore-config",
            "--newline",
            "--progress",
            "--no-color",
            "--no-playlist",
            "--continue",
            "--paths", destinationDirectory.path,
            "--output", outputTemplate,
            "--format", format.id,
            "--progress-template",
            "download:__MD_PROGRESS__|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--progress-template",
            "postprocess:__MD_POSTPROCESS__|%(progress.status)s",
            "--print", "after_move:__MD_FILE__|%(filepath)s"
        ]
        arguments.append(contentsOf: cookieArguments(
            for: cookieSource,
            profileDirectory: cookieProfileDirectory
        ))
        arguments.append(contentsOf: javaScriptRuntimeArguments())
        arguments.append(contentsOf: youtubePlayerArguments(
            for: job.video.webpageURL,
            playerClient: playerClient
        ))

        if let ffmpeg = MediaCoreLocator.ffmpegURL() {
            arguments.append(contentsOf: [
                "--ffmpeg-location",
                ffmpeg.deletingLastPathComponent().path
            ])
        }

        if job.preset == .audio {
            arguments.append(contentsOf: [
                "--extract-audio",
                "--audio-format", "m4a",
                "--audio-quality", "0"
            ])
        }

        let connectionCount = min(max(engineOptions.connectionCount, 2), 16)
        if format.isFragmented {
            arguments.append(contentsOf: [
                "--concurrent-fragments",
                "\(connectionCount)"
            ])
            onMessage("正在使用 \(connectionCount) 路并发分片")
        }

        arguments.append(job.video.webpageURL.absoluteString)
        let nativeArguments = arguments

        if engineOptions.usesMultiConnection,
           !format.isFragmented,
           let aria2 = MediaCoreLocator.aria2cURL() {
            let rpc = Aria2RPCConfiguration(
                port: Int.random(in: 49152...65535),
                secret: UUID().uuidString.replacingOccurrences(of: "-", with: "")
            )
            onMessage("正在使用 \(connectionCount) 路连接下载")
            let aria2Result = try await executeDownload(
                executable: executable,
                arguments: arguments + aria2Arguments(
                    executable: aria2,
                    connectionCount: connectionCount,
                    rpc: rpc
                ),
                onProgress: onProgress,
                onMessage: onMessage,
                aria2RPC: rpc
            )
            if aria2Result.status == 0 {
                return aria2Result
            }
            guard shouldFallbackFromAria2(output: aria2Result.combinedOutput) else {
                throw MediaCoreError.executionFailed(
                    aria2Result.status,
                    aria2Result.combinedOutput
                )
            }
            onMessage("视频源不支持多连接，正在切换兼容下载")
        } else if engineOptions.usesMultiConnection && !format.isFragmented {
            onMessage("未找到多连接组件，正在使用兼容下载")
        }

        let result = try await executeDownload(
            executable: executable,
            arguments: nativeArguments,
            onProgress: onProgress,
            onMessage: onMessage
        )
        guard result.status == 0 else {
            throw MediaCoreError.executionFailed(result.status, result.combinedOutput)
        }
        return result
    }

    private func mergeDownloadedStreams(
        videoURL: URL,
        audioURL: URL,
        videoFormat: DownloadFormat,
        audioFormat: DownloadFormat,
        job: DownloadJob,
        workDirectory: URL
    ) async throws -> URL {
        guard let ffmpeg = MediaCoreLocator.ffmpegURL() else {
            throw MediaCoreError.missingFFmpeg
        }

        let baseName = safeOutputName(job.video)
        let preferredExtension = videoFormat.ext.lowercased() == "mp4"
            && ["mp4", "m4a"].contains(audioFormat.ext.lowercased())
            ? "mp4"
            : "mkv"
        let attemptedExtensions = preferredExtension == "mp4"
            ? ["mp4", "mkv"]
            : ["mkv", "mp4"]
        var lastOutput = ""

        for outputExtension in attemptedExtensions {
            let finalURL = job.destinationDirectory
                .appendingPathComponent("\(baseName).\(outputExtension)")
            if FileManager.default.fileExists(atPath: finalURL.path) {
                return finalURL
            }

            let temporaryOutput = workDirectory
                .appendingPathComponent("merged.\(outputExtension)")
            var arguments = [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-i", videoURL.path,
                "-i", audioURL.path,
                "-map", "0:v:0",
                "-map", "1:a:0",
                "-c", "copy"
            ]
            if outputExtension == "mp4" {
                arguments.append(contentsOf: ["-movflags", "+faststart"])
            }
            arguments.append(temporaryOutput.path)

            let result = try await runner.run(
                executable: ffmpeg,
                arguments: arguments
            )
            if result.status == 0,
               FileManager.default.fileExists(atPath: temporaryOutput.path) {
                try FileManager.default.moveItem(
                    at: temporaryOutput,
                    to: finalURL
                )
                return finalURL
            }
            lastOutput = result.combinedOutput
            try? FileManager.default.removeItem(at: temporaryOutput)
        }

        throw MediaCoreError.executionFailed(
            -1,
            lastOutput.isEmpty ? "无法合并并行下载的视频和音频" : lastOutput
        )
    }

    private func parallelWorkDirectory(for job: DownloadJob) -> URL {
        job.destinationDirectory.appendingPathComponent(
            ".mediadock-parallel-\(job.id.uuidString)",
            isDirectory: true
        )
    }

    private func safeOutputName(_ video: VideoInfo) -> String {
        var title = video.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\0"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = "video"
        }
        return String(title.prefix(150)) + " [\(video.id)]"
    }

    private func executeDownload(
        executable: URL,
        arguments: [String],
        onProgress: @escaping @Sendable (ProgressUpdate) -> Void,
        onMessage: @escaping @Sendable (String) -> Void,
        aria2RPC: Aria2RPCConfiguration? = nil
    ) async throws -> ProcessResult {
        let progressMonitor = aria2RPC.map {
            startAria2ProgressMonitor(configuration: $0, onProgress: onProgress)
        }
        defer { progressMonitor?.cancel() }

        return try await runner.run(
            executable: executable,
            arguments: arguments,
            onStandardOutputLine: { line in
                if let update = downloadProgressUpdate(from: line) {
                    onProgress(update)
                } else if markerPayload(in: line, marker: "__MD_POSTPROCESS__|") != nil {
                    onMessage("正在处理文件")
                }
            },
            onStandardErrorLine: { line in
                if let update = aria2ProgressUpdate(from: line) {
                    onProgress(update)
                } else if line.localizedCaseInsensitiveContains("merging")
                    || line.localizedCaseInsensitiveContains("extracting audio") {
                    onMessage("正在合并与转换")
                }
            }
        )
    }

    private func startAria2ProgressMonitor(
        configuration: Aria2RPCConfiguration,
        onProgress: @escaping @Sendable (ProgressUpdate) -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            var lastShutdown = Date.distantPast

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { break }

                let activeItems = try? await aria2RPCItems(
                    configuration: configuration,
                    method: "aria2.tellActive",
                    extraParameters: []
                )

                if let item = activeItems?.first,
                   let completed = Int64(item.completedLength),
                   let total = Int64(item.totalLength),
                   total > 0 {
                    let speed = Double(item.downloadSpeed) ?? 0
                    let remaining = max(Double(total - completed), 0)
                    onProgress(
                        ProgressUpdate(
                            fraction: min(max(Double(completed) / Double(total), 0), 1),
                            speed: transferRateText(speed),
                            eta: etaText(speed > 0 ? remaining / speed : nil)
                        )
                    )
                    continue
                }

                guard activeItems?.isEmpty == true else { continue }
                let stoppedItems = try? await aria2RPCItems(
                    configuration: configuration,
                    method: "aria2.tellStopped",
                    extraParameters: [0, 10]
                )
                guard stoppedItems?.isEmpty == false else { continue }

                guard Date().timeIntervalSince(lastShutdown) > 1.5 else {
                    continue
                }
                _ = try? await aria2RPCRequest(
                    configuration: configuration,
                    method: "aria2.shutdown",
                    extraParameters: []
                )
                lastShutdown = Date()
            }

            if Task.isCancelled {
                Task.detached(priority: .utility) {
                    _ = try? await aria2RPCRequest(
                        configuration: configuration,
                        method: "aria2.forceShutdown",
                        extraParameters: []
                    )
                }
            }
        }
    }

    private func aria2RPCItems(
        configuration: Aria2RPCConfiguration,
        method: String,
        extraParameters: [Any]
    ) async throws -> [Aria2RPCResult] {
        let fields = [
            "completedLength",
            "totalLength",
            "downloadSpeed",
            "connections",
            "status"
        ]
        let data = try await aria2RPCRequest(
            configuration: configuration,
            method: method,
            extraParameters: extraParameters + [fields]
        )
        return try JSONDecoder().decode(
            Aria2RPCResponse<[Aria2RPCResult]>.self,
            from: data
        ).result ?? []
    }

    private func aria2RPCRequest(
        configuration: Aria2RPCConfiguration,
        method: String,
        extraParameters: [Any]
    ) async throws -> Data {
        guard let url = URL(
            string: "http://127.0.0.1:\(configuration.port)/jsonrpc"
        ) else {
            throw MediaCoreError.invalidResponse("多连接进度服务地址无效")
        }

        let parameters: [Any] = ["token:\(configuration.secret)"] + extraParameters
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "mediadock",
            "method": method,
            "params": parameters
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw MediaCoreError.invalidResponse("无法读取多连接下载状态")
        }
        return data
    }

    private func aria2Arguments(
        executable: URL,
        connectionCount: Int,
        rpc: Aria2RPCConfiguration
    ) -> [String] {
        [
            "--downloader", executable.path,
            "--downloader-args",
            "aria2c:-x\(connectionCount) -s\(connectionCount) -j1 --min-split-size=1M --enable-rpc=true --rpc-listen-all=false --rpc-listen-port=\(rpc.port) --rpc-secret=\(rpc.secret)"
        ]
    }

    private func shouldFallbackFromAria2(output: String) -> Bool {
        output.localizedCaseInsensitiveContains("aria2c exited with code")
            || output.localizedCaseInsensitiveContains("invalid range header")
            || output.localizedCaseInsensitiveContains("does not support range")
    }

    private func downloadedFile(
        from result: ProcessResult,
        in directory: URL
    ) throws -> URL {
        if let fileLine = result.standardOutput
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("__MD_FILE__|") }) {
            let path = String(fileLine.dropFirst("__MD_FILE__|".count))
            let outputURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                return outputURL
            }
        }

        if let newest = newestDownloadedFile(in: directory) {
            return newest
        }

        throw MediaCoreError.invalidResponse("下载已完成，但没有找到输出文件")
    }

    private func version(executable: URL?, arguments: [String]) async -> String? {
        guard let executable else { return nil }
        guard let result = try? await runner.run(executable: executable, arguments: arguments),
              result.status == 0 else {
            return nil
        }

        let firstLine = result.combinedOutput
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return firstLine?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func newestDownloadedFile(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return files
            .filter { url in
                let name = url.lastPathComponent
                return !name.hasSuffix(".part")
                    && !name.hasSuffix(".ytdl")
                    && !name.hasSuffix(".temp")
            }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true, let date = values?.contentModificationDate else {
                    return nil
                }
                return (url, date)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    private func cookieArguments(
        for source: BrowserCookieSource?,
        profileDirectory: URL?
    ) -> [String] {
        guard let name = source?.ytDlpName else { return [] }
        let browserSpecification = profileDirectory.map {
            "\(name):\($0.path)"
        } ?? name
        return ["--cookies-from-browser", browserSpecification]
    }

    private func javaScriptRuntimeArguments() -> [String] {
        guard let runtime = MediaCoreLocator.javaScriptRuntimeURL() else { return [] }
        return ["--js-runtimes", "node:\(runtime.path)"]
    }

    private func youtubePlayerArguments(
        for url: URL,
        playerClient: YouTubePlayerClient?
    ) -> [String] {
        guard let playerClient, isYouTubeURL(url) else { return [] }
        return ["--extractor-args", "youtube:player_client=\(playerClient.rawValue)"]
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }
}

private func cleanProgressValue(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed == "NA" || trimmed == "N/A" ? "" : trimmed
}

private func transferRateText(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "" }
    let units = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
    var value = bytesPerSecond
    var unitIndex = 0

    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }

    if unitIndex == 0 {
        return String(format: "%.0f %@", value, units[unitIndex])
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

private func transferRateBytesPerSecond(_ text: String) -> Double {
    let cleaned = text
        .replacingOccurrences(of: "/s", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return 0 }

    let parts = cleaned.split(separator: " ", maxSplits: 1)
    guard let value = Double(parts[0]) else { return 0 }
    let unit = parts.count > 1 ? String(parts[1]).lowercased() : "b"
    switch unit {
    case "kib": return value * 1_024
    case "mib": return value * 1_048_576
    case "gib": return value * 1_073_741_824
    default: return value
    }
}

private func etaText(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "" }
    let totalSeconds = Int(seconds.rounded())
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

private func downloadProgressUpdate(from line: String) -> ProgressUpdate? {
    guard let payload = markerPayload(in: line, marker: "__MD_PROGRESS__|") else {
        return nil
    }
    let values = payload.split(separator: "|", omittingEmptySubsequences: false)
    guard values.count >= 3 else { return nil }
    let percentText = values[0]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "%", with: "")
    let fraction = (Double(percentText) ?? 0) / 100
    return ProgressUpdate(
        fraction: min(max(fraction, 0), 1),
        speed: cleanProgressValue(String(values[1])),
        eta: cleanProgressValue(String(values[2]))
    )
}

private func aria2ProgressUpdate(from line: String) -> ProgressUpdate? {
    let pattern = #"\[#[^\]]*?\(\s*([0-9]+(?:\.[0-9]+)?)%\)\s+CN:[^\]]*?DL:([^\s\]]+)(?:\s+ETA:([^\s\]]+))?\]"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(line.startIndex..., in: line)
    guard let match = expression.firstMatch(in: line, range: range),
          let percentRange = Range(match.range(at: 1), in: line) else {
        return nil
    }

    let speed = Range(match.range(at: 2), in: line).map { String(line[$0]) } ?? ""
    let eta = Range(match.range(at: 3), in: line).map { String(line[$0]) } ?? ""
    let fraction = (Double(line[percentRange]) ?? 0) / 100
    return ProgressUpdate(
        fraction: min(max(fraction, 0), 1),
        speed: cleanProgressValue(speed),
        eta: cleanProgressValue(eta)
    )
}

private func markerPayload(in line: String, marker: String) -> String? {
    guard let markerRange = line.range(of: marker) else { return nil }
    return String(line[markerRange.upperBound...])
}

private struct YtDlpMetadata: Decodable {
    let id: String?
    let title: String?
    let extractorKey: String?
    let extractor: String?
    let webpageURL: String?
    let originalURL: String?
    let thumbnail: String?
    let duration: Double?
    let isLive: Bool?
    let formats: [YtDlpFormat]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case extractorKey = "extractor_key"
        case extractor
        case webpageURL = "webpage_url"
        case originalURL = "original_url"
        case thumbnail
        case duration
        case isLive = "is_live"
        case formats
    }
}

private struct YtDlpFormat: Decodable {
    let formatID: String?
    let protocolName: String?
    let ext: String?
    let height: Int?
    let tbr: Double?
    let vcodec: String?
    let acodec: String?
    let fileSize: Int64?
    let fileSizeApprox: Int64?

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case protocolName = "protocol"
        case ext
        case height
        case tbr
        case vcodec
        case acodec
        case fileSize = "filesize"
        case fileSizeApprox = "filesize_approx"
    }
}
