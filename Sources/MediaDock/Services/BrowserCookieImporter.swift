import Foundation

enum BrowserCookieImportError: LocalizedError {
    case noCookiesDatabase
    case copyFailed
    case bookmarkFailed
    case backupFailed

    var errorDescription: String? {
        switch self {
        case .noCookiesDatabase:
            return "没有找到浏览器 Cookies 数据库，请选择浏览器数据文件夹"
        case .copyFailed:
            return "复制浏览器登录状态失败"
        case .bookmarkFailed:
            return "无法保存浏览器文件夹的访问授权，请重新选择"
        case .backupFailed:
            return "无法读取最新的浏览器登录状态，请确认浏览器数据文件夹仍然可用"
        }
    }
}

struct ImportedBrowserProfile: Sendable {
    let directory: URL
    let bookmark: Data
}

struct BrowserCookieImporter {
    func bookmark(for directory: URL) throws -> Data {
        let didAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return try directory.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BrowserCookieImportError.bookmarkFailed
        }
    }

    func importProfile(
        fromBookmark bookmark: Data,
        browser: BrowserCookieSource
    ) throws -> ImportedBrowserProfile {
        var isStale = false
        let directory: URL

        do {
            directory = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw BrowserCookieImportError.bookmarkFailed
        }

        let profile = try importProfile(from: directory, browser: browser)
        let refreshedBookmark = isStale ? try self.bookmark(for: directory) : bookmark
        return ImportedBrowserProfile(directory: profile, bookmark: refreshedBookmark)
    }

    func importProfile(
        from selectedDirectory: URL,
        browser: BrowserCookieSource
    ) throws -> URL {
        let didAccess = selectedDirectory.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                selectedDirectory.stopAccessingSecurityScopedResource()
            }
        }

        guard browser != .off else {
            throw BrowserCookieImportError.noCookiesDatabase
        }

        let database = newestCookiesDatabase(in: selectedDirectory)
        guard let database else {
            throw BrowserCookieImportError.noCookiesDatabase
        }

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        let destinationRoot = support
            .appendingPathComponent("MediaDock", isDirectory: true)
            .appendingPathComponent("BrowserProfile-\(browser.rawValue)", isDirectory: true)
        let profileName = database.deletingLastPathComponent().lastPathComponent
        let destinationProfile = destinationRoot.appendingPathComponent(profileName, isDirectory: true)
        let stagingProfile = destinationRoot.appendingPathComponent(
            ".import-\(UUID().uuidString)",
            isDirectory: true
        )
        let previousProfile = destinationRoot.appendingPathComponent(
            ".previous-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(
                at: stagingProfile,
                withIntermediateDirectories: true
            )
            try copyConsistentDatabase(
                from: database,
                to: stagingProfile.appendingPathComponent("Cookies")
            )

            if FileManager.default.fileExists(atPath: destinationProfile.path) {
                try FileManager.default.moveItem(
                    at: destinationProfile,
                    to: previousProfile
                )
            }

            do {
                try FileManager.default.moveItem(
                    at: stagingProfile,
                    to: destinationProfile
                )
            } catch {
                if FileManager.default.fileExists(atPath: previousProfile.path) {
                    try? FileManager.default.moveItem(
                        at: previousProfile,
                        to: destinationProfile
                    )
                }
                throw error
            }

            if FileManager.default.fileExists(atPath: previousProfile.path) {
                try? FileManager.default.removeItem(at: previousProfile)
            }
            return destinationProfile
        } catch let error as BrowserCookieImportError {
            try? FileManager.default.removeItem(at: stagingProfile)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: stagingProfile)
            throw BrowserCookieImportError.copyFailed
        }
    }

    private func copyConsistentDatabase(from source: URL, to destination: URL) throws {
        let sqlite = URL(fileURLWithPath: "/usr/bin/sqlite3")
        guard FileManager.default.isExecutableFile(atPath: sqlite.path) else {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }

        let escapedDestination = destination.path.replacingOccurrences(of: "'", with: "''")
        let process = Process()
        process.executableURL = sqlite
        process.arguments = [
            source.path,
            ".timeout 5000",
            ".backup '\(escapedDestination)'"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BrowserCookieImportError.backupFailed
        }

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: destination.path) else {
            throw BrowserCookieImportError.backupFailed
        }
    }

    private func newestCookiesDatabase(in root: URL) -> URL? {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var candidates: [(URL, Date)] = []

        func consider(_ url: URL) {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            guard values?.isRegularFile == true else { return }
            candidates.append((url, values?.contentModificationDate ?? .distantPast))
        }

        consider(root.appendingPathComponent("Cookies"))

        if let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                let isDirectory = try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                if isDirectory == true {
                    consider(child.appendingPathComponent("Cookies"))
                }
            }
        }

        return candidates.max(by: { $0.1 < $1.1 })?.0
    }
}
