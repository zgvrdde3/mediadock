import AppKit
import Foundation

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: SidebarSection = .downloads
    @Published var linkText = ""
    @Published var parsedVideo: VideoInfo?
    @Published var batchItems: [BatchLinkItem] = []
    @Published var linkInputMode: LinkInputMode = .single
    @Published var selectedPreset: DownloadPreset = .best
    @Published var isParsing = false
    @Published var parseStage = "解析中"
    @Published var jobs: [DownloadJob] = []
    @Published var settings: AppSettings = .defaults
    @Published var coreStatus: CoreStatus = .checking
    @Published var isCheckingCore = false
    @Published var alert: AppAlert?

    private let service = YtDlpService()
    private let store = StateStore()
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var intentionallyPaused = Set<UUID>()

    init() {
        if let saved = store.load() {
            settings = saved.settings
            jobs = saved.jobs.map { job in
                var restored = job
                if restored.status == .downloading || restored.status == .queued {
                    restored.status = .paused
                    restored.message = "上次关闭时尚未完成"
                    restored.speed = ""
                    restored.eta = ""
                }
                return restored
            }
        }

        if settings.multiConnectionDownload == nil {
            settings.usesMultiConnectionDownload = true
        }
        if settings.downloadConnectionCount == nil {
            settings.downloadConnections = 8
        }

        selectedPreset = settings.defaultPreset
        ensureDownloadDirectory()
        saveState()

        Task {
            await refreshCoreStatus()
        }
    }

    var activeJobs: [DownloadJob] {
        jobs.filter { !$0.status.isHistory }
    }

    var historyJobs: [DownloadJob] {
        jobs.filter(\.status.isHistory)
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var activeCount: Int {
        jobs.filter { $0.status == .downloading }.count
    }

    var recentJobs: [DownloadJob] {
        Array(jobs.sorted { $0.createdAt > $1.createdAt }.prefix(4))
    }

    var batchReadyVideos: [VideoInfo] {
        batchItems.compactMap { item in
            item.state == .ready ? item.video : nil
        }
    }

    var batchFinishedCount: Int {
        batchItems.filter { $0.state.isFinished }.count
    }

    var batchFailureCount: Int {
        batchItems.filter {
            $0.state == .failed || $0.state == .duplicate
        }.count
    }

    func parseLink() async {
        let cleaned = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            presentError(title: "链接格式不正确", message: MediaCoreError.invalidLink.localizedDescription)
            return
        }

        isParsing = true
        parseStage = "解析中"
        parsedVideo = nil
        defer { isParsing = false }

        do {
            parsedVideo = try await parseVideo(at: url)
            selectedPreset = settings.defaultPreset
        } catch is CancellationError {
            return
        } catch {
            presentError(title: "解析失败", message: error.localizedDescription)
        }
    }

    func parseBatchLinks() async {
        guard !isParsing else { return }

        let urls = extractVideoLinks(from: linkText)
        guard !urls.isEmpty else {
            presentError(
                title: "没有找到视频链接",
                message: "请每行粘贴一个 http 或 https 视频链接。"
            )
            return
        }
        guard urls.count <= 50 else {
            presentError(
                title: "一次最多解析 50 个链接",
                message: "当前找到 \(urls.count) 个链接，请分成多批粘贴。"
            )
            return
        }

        linkInputMode = .batch
        parsedVideo = nil
        batchItems = urls.map(BatchLinkItem.init)
        selectedPreset = settings.defaultPreset
        await parseBatchItemIndices(Array(batchItems.indices))
    }

    func retryFailedBatchItems() async {
        guard !isParsing else { return }
        let indices = batchItems.indices.filter {
            batchItems[$0].state == .failed
        }
        guard !indices.isEmpty else { return }
        await parseBatchItemIndices(Array(indices))
    }

    func removeBatchItem(_ itemID: UUID) {
        guard !isParsing else { return }
        batchItems.removeAll { $0.id == itemID }
    }

    func discardBatchPreview() {
        guard !isParsing else { return }
        batchItems = []
    }

    func enqueueBatchDownloads() {
        let videos = batchReadyVideos
        guard !videos.isEmpty else {
            presentError(
                title: "没有可下载的视频",
                message: "请先修复解析失败的链接，或重新粘贴其他链接。"
            )
            return
        }

        ensureDownloadDirectory()
        let newJobs = videos.map { video in
            DownloadJob(
                video: video,
                preset: selectedPreset,
                destinationDirectory: settings.downloadDirectory
            )
        }
        jobs.insert(contentsOf: newJobs, at: 0)
        batchItems = []
        linkText = ""
        linkInputMode = .single
        saveState()
        selectedSection = .queue
        pumpQueue()
    }

    func enqueueDownload() {
        guard let video = parsedVideo else {
            presentError(title: "还没有解析视频", message: "请先粘贴链接并完成解析。")
            return
        }

        ensureDownloadDirectory()
        let job = DownloadJob(
            video: video,
            preset: selectedPreset,
            destinationDirectory: settings.downloadDirectory
        )
        jobs.insert(job, at: 0)
        saveState()
        parsedVideo = nil
        linkText = ""
        selectedSection = .queue
        pumpQueue()
    }

    func pause(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        intentionallyPaused.insert(jobID)
        runningTasks[jobID]?.cancel()
        jobs[index].status = .paused
        jobs[index].message = "已暂停，继续时会从已有进度恢复"
        jobs[index].speed = ""
        jobs[index].eta = ""
        saveState()
        pumpQueue()
    }

    func resume(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .queued
        jobs[index].message = "等待继续下载"
        saveState()
        pumpQueue()
    }

    func cancel(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        intentionallyPaused.remove(jobID)
        runningTasks[jobID]?.cancel()
        jobs[index].status = .cancelled
        jobs[index].message = "任务已取消"
        jobs[index].completedAt = Date()
        jobs[index].speed = ""
        jobs[index].eta = ""
        saveState()
        pumpQueue()
    }

    func retry(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .queued
        jobs[index].progress = 0
        jobs[index].speed = ""
        jobs[index].eta = ""
        jobs[index].message = "等待重试"
        jobs[index].outputURL = nil
        jobs[index].completedAt = nil
        saveState()
        pumpQueue()
    }

    func remove(_ jobID: UUID) {
        runningTasks[jobID]?.cancel()
        runningTasks[jobID] = nil
        jobs.removeAll { $0.id == jobID }
        saveState()
        pumpQueue()
    }

    func clearHistory() {
        jobs.removeAll { $0.status.isHistory }
        saveState()
    }

    func importBrowserLogin(from directory: URL) {
        guard let browser = settings.cookieSource, browser != .off else {
            presentError(title: "没有选择浏览器", message: "请先在设置中选择 Chrome。")
            return
        }

        do {
            let importer = BrowserCookieImporter()
            let bookmark = try importer.bookmark(for: directory)
            let profile = try importer.importProfile(
                from: directory,
                browser: browser
            )
            settings.browserProfileDirectoryPath = profile.path
            settings.browserProfileImportedAt = Date()
            settings.browserProfileSourceBookmark = bookmark
            saveState()
        } catch {
            presentError(title: "同步登录状态失败", message: error.localizedDescription)
        }
    }

    func refreshCoreStatus() async {
        isCheckingCore = true

        let ytDlpPath = MediaCoreLocator.ytDlpURL()?.path
        let ffmpegPath = MediaCoreLocator.ffmpegURL()?.path
        let javaScriptPath = MediaCoreLocator.javaScriptRuntimeURL()?.path
        coreStatus = CoreStatus(
            ytDlpVersion: coreStatus.ytDlpVersion,
            ffmpegVersion: coreStatus.ffmpegVersion,
            javaScriptVersion: coreStatus.javaScriptVersion,
            aria2Version: coreStatus.aria2Version,
            ytDlpPath: ytDlpPath,
            ffmpegPath: ffmpegPath,
            javaScriptPath: javaScriptPath,
            aria2Path: MediaCoreLocator.aria2cURL()?.path,
            errorMessage: ytDlpPath == nil ? MediaCoreError.missingYTDLP.localizedDescription : nil
        )

        coreStatus = await service.checkCore()
        isCheckingCore = false
    }

    func ensureDownloadDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: settings.downloadDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            settings.downloadDirectory = AppSettings.defaults.downloadDirectory
            try? FileManager.default.createDirectory(
                at: settings.downloadDirectory,
                withIntermediateDirectories: true
            )
            presentError(title: "无法创建下载文件夹", message: error.localizedDescription)
        }
    }

    func settingsDidChange() {
        ensureDownloadDirectory()
        saveState()
        pumpQueue()
    }

    func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealFile(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openDownloadFolder() {
        NSWorkspace.shared.open(settings.downloadDirectory)
    }

    private func pumpQueue() {
        let limit = max(1, min(settings.maxConcurrentDownloads, 4))
        var available = limit - runningTasks.count

        while available > 0 {
            guard let next = jobs.first(where: { $0.status == .queued }) else { break }
            start(next.id)
            available -= 1
        }
    }

    private func start(_ jobID: UUID) {
        guard runningTasks[jobID] == nil,
              let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }

        jobs[index].status = .downloading
        jobs[index].message = "正在连接视频源"
        let job = jobs[index]
        saveState()

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let outputURL = try await downloadWithAutomaticLogin(
                    job: job,
                    onProgress: { update in
                        Task { @MainActor in
                            self.applyProgress(update, to: jobID)
                        }
                    },
                    onMessage: { message in
                        Task { @MainActor in
                            self.applyMessage(message, to: jobID)
                        }
                    }
                )

                guard !Task.isCancelled else {
                    throw CancellationError()
                }
                finish(jobID, outputURL: outputURL)
            } catch is CancellationError {
                handleCancellation(jobID)
            } catch {
                fail(jobID, message: error.localizedDescription)
            }
        }

        runningTasks[jobID] = task
    }

    private func parseVideo(
        at url: URL,
        refreshLogin: Bool = true,
        progressLabel: String? = nil
    ) async throws -> VideoInfo {
        guard let cookieSource = settings.cookieSource,
              cookieSource.ytDlpName != nil else {
            return try await service.parse(url: url)
        }

        let canAutoRefresh = settings.browserProfileSourceBookmark != nil
        if canAutoRefresh && refreshLogin {
            parseStage = parseStageText(
                "同步最新 \(cookieSource.title) 登录状态",
                progressLabel: progressLabel
            )
            _ = refreshBrowserLoginSnapshot()
        }

        let clients: [YouTubePlayerClient?] = isYouTubeURL(url)
            ? [nil, .webEmbedded]
            : [nil]
        var lastError: Error?

        for (index, playerClient) in clients.enumerated() {
            parseStage = parseStageText(
                index == 0 ? "解析中" : "页面数据不完整，切换兼容入口",
                progressLabel: progressLabel
            )
            do {
                return try await parseAttempt(
                    url: url,
                    cookieSource: cookieSource,
                    playerClient: playerClient,
                    canAutoRefresh: canAutoRefresh,
                    progressLabel: progressLabel
                )
            } catch let error as MediaCoreError
                where error.isTransientYouTubePlayerFailure && index == 0 {
                lastError = error
                if canAutoRefresh {
                    _ = refreshBrowserLoginSnapshot()
                }
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                throw error
            }
        }

        throw lastError ?? MediaCoreError.invalidResponse("YouTube 没有返回可用的视频数据")
    }

    private func parseAttempt(
        url: URL,
        cookieSource: BrowserCookieSource,
        playerClient: YouTubePlayerClient?,
        canAutoRefresh: Bool,
        progressLabel: String?
    ) async throws -> VideoInfo {
        do {
            return try await service.parse(
                url: url,
                cookieSource: cookieSource,
                cookieProfileDirectory: browserProfileURL,
                playerClient: playerClient
            )
        } catch let error as MediaCoreError where error.requiresAuthentication {
            parseStage = parseStageText(
                "刷新登录状态后重试",
                progressLabel: progressLabel
            )
            guard canAutoRefresh, refreshBrowserLoginSnapshot() else {
                throw error
            }
            return try await service.parse(
                url: url,
                cookieSource: cookieSource,
                cookieProfileDirectory: browserProfileURL,
                playerClient: playerClient
            )
        }
    }

    private func parseBatchItemIndices(_ indices: [Int]) async {
        guard !indices.isEmpty else { return }

        isParsing = true
        defer { isParsing = false }

        if let cookieSource = settings.cookieSource,
           cookieSource.ytDlpName != nil,
           settings.browserProfileSourceBookmark != nil {
            parseStage = "同步最新 \(cookieSource.title) 登录状态"
            _ = refreshBrowserLoginSnapshot()
        }

        for (offset, index) in indices.enumerated() {
            guard batchItems.indices.contains(index) else { continue }
            batchItems[index].state = .parsing
            batchItems[index].errorMessage = nil

            let label = "批量 \(offset + 1)/\(indices.count)"
            do {
                let video = try await parseVideo(
                    at: batchItems[index].url,
                    refreshLogin: false,
                    progressLabel: label
                )

                let isDuplicate = batchItems.indices.contains { otherIndex in
                    guard otherIndex != index,
                          let existing = batchItems[otherIndex].video else {
                        return false
                    }
                    return existing.id == video.id && existing.source == video.source
                }

                if isDuplicate {
                    batchItems[index].state = .duplicate
                    batchItems[index].video = nil
                    batchItems[index].errorMessage = "重复视频，已跳过"
                } else {
                    batchItems[index].state = .ready
                    batchItems[index].video = video
                }
            } catch is CancellationError {
                batchItems[index].state = .pending
                return
            } catch {
                batchItems[index].state = .failed
                batchItems[index].errorMessage = error.localizedDescription
            }
        }
    }

    private func parseStageText(_ message: String, progressLabel: String?) -> String {
        guard let progressLabel else { return message }
        return "\(progressLabel) · \(message)"
    }

    private func downloadWithAutomaticLogin(
        job: DownloadJob,
        onProgress: @escaping @Sendable (ProgressUpdate) -> Void,
        onMessage: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let cookieSource = settings.cookieSource
        let canAutoRefresh = cookieSource?.ytDlpName != nil
            && settings.browserProfileSourceBookmark != nil
        if canAutoRefresh {
            onMessage("正在同步最新浏览器登录状态")
            _ = refreshBrowserLoginSnapshot()
        }

        let fallbackClient: YouTubePlayerClient = job.preset == .audio
            ? .web
            : .webEmbedded
        let clients: [YouTubePlayerClient?] = isYouTubeURL(job.video.webpageURL)
            ? [nil, fallbackClient]
            : [nil]
        var lastError: Error?

        for (index, playerClient) in clients.enumerated() {
            if index > 0 {
                onMessage("页面数据不完整，正在切换兼容下载入口")
                try await Task.sleep(for: .milliseconds(700))
            }

            do {
                return try await downloadAttempt(
                    job: job,
                    cookieSource: cookieSource,
                    canAutoRefresh: canAutoRefresh,
                    playerClient: playerClient,
                    onProgress: onProgress,
                    onMessage: onMessage
                )
            } catch let error as MediaCoreError
                where error.isTransientYouTubePlayerFailure && index == 0 {
                lastError = error
                if canAutoRefresh {
                    _ = refreshBrowserLoginSnapshot()
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? MediaCoreError.invalidResponse("YouTube 没有返回可用的下载数据")
    }

    private func downloadAttempt(
        job: DownloadJob,
        cookieSource: BrowserCookieSource?,
        canAutoRefresh: Bool,
        playerClient: YouTubePlayerClient?,
        onProgress: @escaping @Sendable (ProgressUpdate) -> Void,
        onMessage: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        do {
            return try await service.download(
                job: job,
                cookieSource: cookieSource,
                cookieProfileDirectory: browserProfileURL,
                playerClient: playerClient,
                engineOptions: downloadEngineOptions,
                onProgress: onProgress,
                onMessage: onMessage
            )
        } catch let error as MediaCoreError where error.requiresAuthentication {
            guard let cookieSource,
                  canAutoRefresh,
                  refreshBrowserLoginSnapshot() else {
                throw error
            }
            onMessage("登录状态已刷新，正在重试")
            return try await service.download(
                job: job,
                cookieSource: cookieSource,
                cookieProfileDirectory: browserProfileURL,
                playerClient: playerClient,
                engineOptions: downloadEngineOptions,
                onProgress: onProgress,
                onMessage: onMessage
            )
        }
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    @discardableResult
    private func refreshBrowserLoginSnapshot() -> Bool {
        guard let browser = settings.cookieSource,
              browser != .off,
              let bookmark = settings.browserProfileSourceBookmark else {
            return false
        }

        do {
            let imported = try BrowserCookieImporter().importProfile(
                fromBookmark: bookmark,
                browser: browser
            )
            settings.browserProfileDirectoryPath = imported.directory.path
            settings.browserProfileImportedAt = Date()
            settings.browserProfileSourceBookmark = imported.bookmark
            saveState()
            return true
        } catch {
            return false
        }
    }

    private var downloadEngineOptions: DownloadEngineOptions {
        DownloadEngineOptions(
            usesMultiConnection: settings.usesMultiConnectionDownload,
            connectionCount: settings.downloadConnections
        )
    }

    private func applyProgress(_ update: ProgressUpdate, to jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].status == .downloading else {
            return
        }

        jobs[index].progress = update.fraction
        jobs[index].speed = update.speed
        jobs[index].eta = update.eta
        jobs[index].message = update.fraction >= 0.999 ? "正在完成文件处理" : "正在下载视频"
    }

    private func applyMessage(_ message: String, to jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].status == .downloading else {
            return
        }
        jobs[index].message = message
    }

    private func finish(_ jobID: UUID, outputURL: URL) {
        runningTasks[jobID] = nil
        intentionallyPaused.remove(jobID)

        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[index].status = .completed
            jobs[index].progress = 1
            jobs[index].speed = ""
            jobs[index].eta = ""
            jobs[index].message = "下载完成"
            jobs[index].outputURL = outputURL
            jobs[index].completedAt = Date()
        }

        saveState()
        if settings.playSoundOnCompletion {
            NSSound(named: "Glass")?.play()
        }
        if settings.openFolderOnCompletion {
            revealFile(outputURL)
        }
        pumpQueue()
    }

    private func fail(_ jobID: UUID, message: String) {
        runningTasks[jobID] = nil
        intentionallyPaused.remove(jobID)

        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[index].status = .failed
            jobs[index].message = message
            jobs[index].speed = ""
            jobs[index].eta = ""
            jobs[index].completedAt = Date()
        }

        saveState()
        pumpQueue()
    }

    private func handleCancellation(_ jobID: UUID) {
        runningTasks[jobID] = nil
        defer { pumpQueue() }

        guard intentionallyPaused.remove(jobID) != nil,
              let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].status != .cancelled else {
            return
        }

        jobs[index].status = .paused
        jobs[index].message = "已暂停，继续时会从已有进度恢复"
        jobs[index].speed = ""
        jobs[index].eta = ""
        saveState()
    }

    private func saveState() {
        do {
            try store.save(PersistedState(settings: settings, jobs: jobs))
        } catch {
            alert = AppAlert(title: "无法保存本地记录", message: error.localizedDescription)
        }
    }

    private func presentError(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    private var browserProfileURL: URL? {
        settings.browserProfileDirectoryPath.map(URL.init(fileURLWithPath:))
    }
}
