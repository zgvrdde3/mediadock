import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var directoryBinding: Binding<URL> {
        Binding(
            get: { model.settings.downloadDirectory },
            set: {
                model.settings.downloadDirectory = $0
                model.settingsDidChange()
            }
        )
    }

    private var presetBinding: Binding<DownloadPreset> {
        Binding(
            get: { model.settings.defaultPreset },
            set: {
                model.settings.defaultPreset = $0
                model.selectedPreset = $0
                model.settingsDidChange()
            }
        )
    }

    private var concurrencyBinding: Binding<Int> {
        Binding(
            get: { model.settings.maxConcurrentDownloads },
            set: {
                model.settings.maxConcurrentDownloads = $0
                model.settingsDidChange()
            }
        )
    }

    private var multiConnectionBinding: Binding<Bool> {
        Binding(
            get: { model.settings.usesMultiConnectionDownload },
            set: {
                model.settings.usesMultiConnectionDownload = $0
                model.settingsDidChange()
            }
        )
    }

    private var connectionCountBinding: Binding<Int> {
        Binding(
            get: { model.settings.downloadConnections },
            set: {
                model.settings.downloadConnections = $0
                model.settingsDidChange()
            }
        )
    }

    private var soundBinding: Binding<Bool> {
        Binding(
            get: { model.settings.playSoundOnCompletion },
            set: {
                model.settings.playSoundOnCompletion = $0
                model.settingsDidChange()
            }
        )
    }

    private var folderBinding: Binding<Bool> {
        Binding(
            get: { model.settings.openFolderOnCompletion },
            set: {
                model.settings.openFolderOnCompletion = $0
                model.settingsDidChange()
            }
        )
    }

    private var cookieSourceBinding: Binding<BrowserCookieSource> {
        Binding(
            get: { model.settings.cookieSource ?? .off },
            set: {
                model.settings.cookieSource = $0 == .off ? nil : $0
                model.settings.browserProfileDirectoryPath = nil
                model.settings.browserProfileImportedAt = nil
                model.settings.browserProfileSourceBookmark = nil
                model.settingsDidChange()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "Preferences",
                    title: "设置",
                    subtitle: "调整默认保存方式，或检查视频下载核心的状态。"
                )

                settingsCard(
                    title: "下载",
                    symbol: "arrow.down.circle"
                ) {
                    VStack(spacing: 17) {
                        settingRow(
                            title: "保存位置",
                            subtitle: model.settings.downloadDirectory.path
                        ) {
                            HStack(spacing: 8) {
                                Button("选择") {
                                    chooseFolder()
                                }
                                .buttonStyle(SecondaryButtonStyle())

                                Button {
                                    model.openDownloadFolder()
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }

                        Divider()

                        settingRow(
                            title: "默认画质",
                            subtitle: "解析新链接时自动选中"
                        ) {
                            Picker("", selection: presetBinding) {
                                ForEach(DownloadPreset.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        Divider()

                        settingRow(
                            title: "同时下载",
                            subtitle: "建议保持 1–2 个，避免占用过多网络"
                        ) {
                            Stepper(
                                "\(concurrencyBinding.wrappedValue) 个任务",
                                value: concurrencyBinding,
                                in: 1...4
                            )
                            .fixedSize()
                        }

                        Divider()

                        settingRow(
                            title: "多连接下载",
                            subtitle: model.coreStatus.canDownloadWithMultipleConnections
                                ? "把单个视频拆成多个连接；不支持时自动回退"
                                : "内置 aria2 不可用，将自动使用兼容下载"
                        ) {
                            Toggle("", isOn: multiConnectionBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!model.coreStatus.canDownloadWithMultipleConnections)
                        }

                        if model.settings.usesMultiConnectionDownload,
                           model.coreStatus.canDownloadWithMultipleConnections {
                            Divider()

                            settingRow(
                                title: "下载连接数",
                                subtitle: "4–8 路通常比较均衡，过高可能被站点限流"
                            ) {
                                Stepper(
                                    "\(connectionCountBinding.wrappedValue) 路",
                                    value: connectionCountBinding,
                                    in: 2...16
                                )
                                .fixedSize()
                            }
                        }
                    }
                }

                settingsCard(
                    title: "完成后",
                    symbol: "checkmark.circle"
                ) {
                    VStack(spacing: 14) {
                        HStack {
                            Text("完成后在 Finder 中显示文件")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Toggle("", isOn: folderBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        Divider()
                        HStack {
                            Text("播放完成提示音")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Toggle("", isOn: soundBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                settingsCard(
                    title: "平台登录",
                    symbol: "person.crop.circle.badge.checkmark"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        settingRow(
                            title: "自动使用登录状态",
                            subtitle: "授权一次浏览器文件夹，之后自动读取最新 Cookies"
                        ) {
                            Picker("", selection: cookieSourceBinding) {
                                ForEach(BrowserCookieSource.supportedLoginSources) { source in
                                    Text(source.title).tag(source)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        if cookieSourceBinding.wrappedValue != .off {
                            Divider()

                            HStack(alignment: .top, spacing: 12) {
                                Label(
                                    cookieStatusText,
                                    systemImage: "lock.shield"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 10)

                                Button(
                                    model.settings.browserProfileSourceBookmark == nil
                                        ? "授权并同步"
                                        : "更换登录来源"
                                ) {
                                    chooseBrowserProfile()
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                }

                CoreStatusCard()

                settingsCard(
                    title: "使用说明",
                    symbol: "info.circle"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            "MediaDock 使用 yt-dlp 解析公开链接，可选 aria2 多连接下载，并用 ffmpeg 合并音视频。",
                            systemImage: "shield.lefthalf.filled"
                        )
                        Label(
                            "请只下载你拥有版权或已获得授权保存的内容。",
                            systemImage: "checkmark.seal"
                        )
                        Label(
                            "不会绕过 DRM、付费墙或人机验证。登录状态仅用于访问你自己的授权内容。",
                            systemImage: "lock.shield"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Text("MediaDock 0.1.0")
                    Spacer()
                    Text("Based on yt-dlp + aria2")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .padding(30)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择默认下载文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.settings.downloadDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        directoryBinding.wrappedValue = url
    }

    private var cookieStatusText: String {
        if model.settings.browserProfileSourceBookmark != nil,
           let importedAt = model.settings.browserProfileImportedAt {
            return "自动同步已开启，上次读取：\(importedAt.formatted(date: .abbreviated, time: .shortened))。解析和下载前会自动更新，Cookies 不会上传。"
        }
        if model.settings.browserProfileDirectoryPath != nil {
            return "已有一份旧登录状态。请再选择一次浏览器数据文件夹，以启用自动同步。"
        }
        return "只需选择一次浏览器数据文件夹。之后 App 会自动读取最新 Cookies，不会上传。"
    }

    private func chooseBrowserProfile() {
        let panel = NSOpenPanel()
        panel.title = "选择浏览器数据文件夹"
        panel.prompt = "授权"
        panel.message = "只需授权一次；以后解析前会自动读取最新登录状态"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importBrowserLogin(from: url)
    }

    private func settingRow<Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            trailing()
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary)
            content()
        }
        .cardSurface(padding: 20)
    }
}

private struct CoreStatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("媒体核心", systemImage: "cpu")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button {
                    Task {
                        await model.refreshCoreStatus()
                    }
                } label: {
                    Label(
                        model.isCheckingCore ? "检查中" : "重新检查",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isCheckingCore)
            }

            VStack(spacing: 0) {
                coreRow(
                    name: "yt-dlp",
                    value: model.coreStatus.ytDlpPath,
                    version: model.coreStatus.ytDlpVersion,
                    fallback: "未找到"
                )

                Divider()
                    .padding(.leading, 26)

                coreRow(
                    name: "ffmpeg",
                    value: model.coreStatus.ffmpegPath,
                    version: model.coreStatus.ffmpegVersion,
                    fallback: "未找到（将无法合并高清音视频）"
                )

                Divider()
                    .padding(.leading, 26)

                coreRow(
                    name: "node",
                    value: model.coreStatus.javaScriptPath,
                    version: model.coreStatus.javaScriptVersion,
                    fallback: "未找到（YouTube 部分格式将不可用）"
                )

                Divider()
                    .padding(.leading, 26)

                coreRow(
                    name: "aria2",
                    value: model.coreStatus.aria2Path,
                    version: model.coreStatus.aria2Version,
                    fallback: "未找到（将只使用单连接下载）"
                )
            }
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))

            if let error = model.coreStatus.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .cardSurface(padding: 20)
    }

    private func coreRow(
        name: String,
        value: String?,
        version: String?,
        fallback: String
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(value == nil ? Color.orange : Color.green)
                .frame(width: 7, height: 7)

            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(version ?? (value == nil ? fallback : "正在读取版本…"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let value {
                    Text(value)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
