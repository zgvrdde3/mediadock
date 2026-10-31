import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    PageHeader(
                        eyebrow: "Quick Download",
                        title: "下载视频",
                        subtitle: "粘贴链接，选择合适的画质，剩下的交给我们。"
                    )

                    Spacer()

                    Button {
                        model.openDownloadFolder()
                    } label: {
                        Label("打开文件夹", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if !model.batchItems.isEmpty {
                    BatchPreviewCard()
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let video = model.parsedVideo {
                    ParsedVideoCard(video: video)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    LinkInputCard()
                }

                if !model.recentJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最近任务")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Button("查看全部") {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    model.selectedSection = .queue
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(model.recentJobs.enumerated()), id: \.element.id) { index, job in
                                CompactJobRow(job: job)
                                if index < model.recentJobs.count - 1 {
                                    Divider()
                                        .padding(.leading, 72)
                                }
                            }
                        }
                        .cardSurface(padding: 8)
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .animation(.easeOut(duration: 0.22), value: model.parsedVideo != nil)
        .animation(.easeOut(duration: 0.22), value: model.batchItems.isEmpty)
    }
}

private struct LinkInputCard: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var inputIsFocused: Bool
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.linkInputMode == .batch ? "批量视频链接" : "视频链接")
                        .font(.system(size: 14, weight: .semibold))
                    Text(
                        model.linkInputMode == .batch
                            ? "每行一个链接，自动去重并逐个解析，最多 50 个"
                            : "支持 yt-dlp 可解析的公开单视频链接"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("输入模式", selection: $model.linkInputMode) {
                    Text("单个").tag(LinkInputMode.single)
                    Text("批量").tag(LinkInputMode.batch)
                }
                .pickerStyle(.segmented)
                .frame(width: 136)
            }

            HStack(alignment: .bottom, spacing: 10) {
                inputField

                Button(action: pasteFromClipboard) {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(action: parse) {
                    HStack(spacing: 7) {
                        if model.isParsing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        Text(
                            model.isParsing
                                ? model.parseStage
                                : (model.linkInputMode == .batch ? "批量解析" : "解析")
                        )
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isParsing || extractedLinkCount == 0)
            }

            HStack(spacing: 8) {
                Label(
                    model.linkInputMode == .batch
                        ? "可直接粘贴多行，或拖入包含多个链接的文本"
                        : "也可以把链接直接拖到这里",
                    systemImage: "cursorarrow.rays"
                )
                Spacer()
                Text("请只下载你有权保存的内容")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .cardSurface(padding: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isDropTarget ? Color.accentColor.opacity(0.72) : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
        }
        .onDrop(of: [UTType.url.identifier, UTType.text.identifier], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            receiveDrop(provider)
            return true
        }
        .onAppear {
            inputIsFocused = model.linkText.isEmpty
        }
        .onChange(of: model.linkInputMode) {
            inputIsFocused = true
        }
    }

    @ViewBuilder
    private var inputField: some View {
        if model.linkInputMode == .batch {
            ZStack(alignment: .topLeading) {
                if model.linkText.isEmpty {
                    Text("每行粘贴一个视频链接，例如：\nhttps://…\nhttps://…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $model.linkText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13))
                    .focused($inputIsFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                if !model.linkText.isEmpty {
                    Button {
                        model.linkText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(minHeight: 108, maxHeight: 132)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        inputIsFocused || isDropTarget
                            ? Color.accentColor.opacity(0.65)
                            : Color.primary.opacity(0.08),
                        lineWidth: inputIsFocused || isDropTarget ? 1.5 : 1
                    )
            }
        } else {
            HStack(spacing: 9) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("粘贴视频链接，例如 https://…", text: $model.linkText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($inputIsFocused)
                    .onSubmit(parse)

                if !model.linkText.isEmpty {
                    Button {
                        model.linkText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        inputIsFocused || isDropTarget
                            ? Color.accentColor.opacity(0.65)
                            : Color.primary.opacity(0.08),
                        lineWidth: inputIsFocused || isDropTarget ? 1.5 : 1
                    )
            }
        }
    }

    private var extractedLinkCount: Int {
        extractVideoLinks(from: model.linkText).count
    }

    private func parse() {
        guard !model.isParsing else { return }
        Task {
            if model.linkInputMode == .batch || extractedLinkCount > 1 {
                await model.parseBatchLinks()
            } else {
                await model.parseLink()
            }
        }
    }

    private func pasteFromClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        let links = extractVideoLinks(from: raw)
        if links.count > 1 {
            model.linkInputMode = .batch
            model.linkText = links.map(\.absoluteString).joined(separator: "\n")
        } else {
            model.linkText = links.first?.absoluteString ?? extractLink(from: raw) ?? raw
        }
        inputIsFocused = true
    }

    private func receiveDrop(_ provider: NSItemProvider) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object as URL? else { return }
                Task { @MainActor in
                    model.linkText = url.absoluteString
                    if model.linkInputMode == .batch {
                        await model.parseBatchLinks()
                    } else {
                        await model.parseLink()
                    }
                }
            }
        } else {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier) { item, _ in
                let text: String?
                if let string = item as? String {
                    text = string
                } else if let data = item as? Data {
                    text = String(data: data, encoding: .utf8)
                } else {
                    text = nil
                }

                guard let text else { return }
                Task { @MainActor in
                    let links = extractVideoLinks(from: text)
                    model.linkText = links.count > 1
                        ? links.map(\.absoluteString).joined(separator: "\n")
                        : (links.first?.absoluteString ?? text)
                    if model.linkInputMode == .batch || links.count > 1 {
                        await model.parseBatchLinks()
                    } else {
                        await model.parseLink()
                    }
                }
            }
        }
    }
}

private struct BatchPreviewCard: View {
    @EnvironmentObject private var model: AppModel

    private var readyCount: Int {
        model.batchReadyVideos.count
    }

    private var failedCount: Int {
        model.batchItems.filter { $0.state == .failed }.count
    }

    private var progress: Double {
        guard !model.batchItems.isEmpty else { return 0 }
        return Double(model.batchFinishedCount) / Double(model.batchItems.count)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("批量预览")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(
                        model.isParsing
                            ? model.parseStage
                            : "已处理 \(model.batchFinishedCount)/\(model.batchItems.count) 个链接"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(readyCount) 个可下载")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(readyCount > 0 ? Color.green : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        (readyCount > 0 ? Color.green : Color.secondary)
                            .opacity(0.11),
                        in: Capsule()
                    )

                Button("返回修改") {
                    withAnimation(.easeOut(duration: 0.18)) {
                        model.discardBatchPreview()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .disabled(model.isParsing)
            }

            if model.isParsing {
                VStack(spacing: 7) {
                    DownloadProgressBar(
                        progress: progress,
                        height: 7,
                        showsIndeterminate: true
                    )

                    HStack {
                        Text("正在逐个解析，失败的项目不会影响后面的链接")
                        Spacer()
                        Text("\(Int((progress * 100).rounded()))%")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.batchItems.enumerated()), id: \.element.id) { index, item in
                        BatchItemRow(item: item)
                        if index < model.batchItems.count - 1 {
                            Divider()
                                .padding(.leading, 100)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }

            Divider()

            HStack(spacing: 7) {
                Text("统一画质")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(DownloadPreset.allCases) { preset in
                    PresetButton(
                        preset: preset,
                        isSelected: model.selectedPreset == preset
                    ) {
                        withAnimation(.easeOut(duration: 0.14)) {
                            model.selectedPreset = preset
                        }
                    }
                }

                Spacer()

                if failedCount > 0 {
                    Button {
                        Task { await model.retryFailedBatchItems() }
                    } label: {
                        Label("重试失败项", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isParsing)
                    .help("只重新解析当前失败的项目")
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("保存到")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(model.settings.downloadDirectory.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("更改") {
                    chooseFolder()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)

                Spacer()

                if model.batchFailureCount > 0 {
                    Text("\(model.batchFailureCount) 个失败或重复项不会加入")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    model.enqueueBatchDownloads()
                } label: {
                    Label(
                        "全部加入队列（\(readyCount)）",
                        systemImage: "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isParsing || readyCount == 0 || !model.coreStatus.isReady)
            }
        }
        .cardSurface(padding: 22)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择视频保存位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.settings.downloadDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.settings.downloadDirectory = url
        model.settingsDidChange()
    }
}

private struct BatchItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: BatchLinkItem

    var body: some View {
        HStack(spacing: 12) {
            if let video = item.video {
                MediaThumbnail(url: video.thumbnailURL, width: 76, height: 44)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                    Image(systemName: stateSymbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(stateColor)
                }
                .frame(width: 76, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.video?.title ?? displayURL)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: stateSymbol)
                        .foregroundStyle(stateColor)

                    Text(stateText)
                        .foregroundStyle(stateColor)
                        .lineLimit(1)

                    if let video = item.video {
                        Text("·")
                        Text(video.source)
                        Text("·")
                        Text(video.durationText)
                        Text("·")
                        Text(video.qualityText)
                    }
                }
                .font(.caption2)
            }

            Spacer()

            if item.state == .ready {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            IconActionButton(symbol: "xmark", help: "从本批次移除") {
                model.removeBatchItem(item.id)
            }
            .disabled(model.isParsing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var displayURL: String {
        if let host = item.url.host {
            return "\(host)\(item.url.path)"
        }
        return item.url.absoluteString
    }

    private var stateSymbol: String {
        switch item.state {
        case .pending: "clock"
        case .parsing: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .duplicate: "minus.circle.fill"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .pending, .parsing: .secondary
        case .ready: .green
        case .failed: .red
        case .duplicate: .orange
        }
    }

    private var stateText: String {
        switch item.state {
        case .pending: "等待解析"
        case .parsing: "解析中"
        case .ready: "可以下载"
        case .failed: item.errorMessage ?? "解析失败"
        case .duplicate: item.errorMessage ?? "重复视频，已跳过"
        }
    }
}

private struct ParsedVideoCard: View {
    @EnvironmentObject private var model: AppModel
    let video: VideoInfo

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 22) {
                MediaThumbnail(url: video.thumbnailURL, width: 286, height: 161)
                    .overlay(alignment: .bottomTrailing) {
                        if let duration = video.duration, duration > 0 {
                            Text(video.durationText)
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.68), in: Capsule())
                                .padding(8)
                        }
                    }

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text(video.source.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.9)
                            .foregroundStyle(Color.accentColor)

                        Spacer()

                        Button("更换链接") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                model.parsedVideo = nil
                                model.linkText = ""
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }

                    Text(video.title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(3)
                        .textSelection(.enabled)

                    HStack(spacing: 14) {
                        Label(video.durationText, systemImage: "clock")
                        Label(video.qualityText, systemImage: "rectangle.inset.filled")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 6)

                    HStack(spacing: 7) {
                        ForEach(DownloadPreset.allCases) { preset in
                            PresetButton(
                                preset: preset,
                                isSelected: model.selectedPreset == preset
                            ) {
                                withAnimation(.easeOut(duration: 0.14)) {
                                    model.selectedPreset = preset
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("保存到")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(model.settings.downloadDirectory.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("更改") {
                    chooseFolder()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)

                Spacer()

                Button {
                    model.enqueueDownload()
                } label: {
                    Label("加入下载队列", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.coreStatus.isReady)
                .help(model.coreStatus.isReady ? "立即开始下载" : "下载核心尚未就绪")
            }
        }
        .cardSurface(padding: 22)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择视频保存位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.settings.downloadDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.settings.downloadDirectory = url
        model.settingsDidChange()
    }
}

private struct PresetButton: View {
    let preset: DownloadPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: preset.symbol)
                Text(preset.title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(preset.subtitle)
    }
}

struct CompactJobRow: View {
    @EnvironmentObject private var model: AppModel
    let job: DownloadJob

    var body: some View {
        HStack(spacing: 12) {
            MediaThumbnail(url: job.video.thumbnailURL, width: 54, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.video.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    if job.status == .downloading {
                        DownloadProgressBar(
                            progress: job.progress,
                            height: 5,
                            showsIndeterminate: true
                        )
                        .frame(maxWidth: 120)
                        Text(compactProgressText(for: job.progress))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(job.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            StatusPill(status: job.status)

            if job.status == .completed, let outputURL = job.outputURL {
                IconActionButton(symbol: "folder", help: "在 Finder 中显示") {
                    model.revealFile(outputURL)
                }
            } else if job.status == .downloading {
                IconActionButton(symbol: "pause.fill", help: "暂停") {
                    model.pause(job.id)
                }
            } else if job.status == .paused {
                IconActionButton(symbol: "play.fill", help: "继续") {
                    model.resume(job.id)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func compactProgressText(for progress: Double) -> String {
        if progress > 0 && progress < 0.1 {
            return String(format: "%.1f%%", progress * 100)
        }
        return "\(Int((progress * 100).rounded()))%"
    }
}

func extractLink(from text: String) -> String? {
    extractVideoLinks(from: text).first?.absoluteString
}
