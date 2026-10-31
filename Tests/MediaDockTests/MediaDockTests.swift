import XCTest
@testable import MediaDock

final class MediaDockTests: XCTestCase {
    func testDurationFormatting() {
        let info = VideoInfo(
            id: "sample",
            title: "Sample",
            source: "Example",
            webpageURL: URL(string: "https://example.com/video")!,
            thumbnailURL: nil,
            duration: 3723,
            qualities: [1080, 720],
            isLive: false
        )

        XCTAssertEqual(info.durationText, "1:02:03")
    }

    func testQualityFormatting() {
        let info = VideoInfo(
            id: "sample",
            title: "Sample",
            source: "Example",
            webpageURL: URL(string: "https://example.com/video")!,
            thumbnailURL: nil,
            duration: 60,
            qualities: [2160, 1080, 720, 480, 360],
            isLive: false
        )

        XCTAssertEqual(info.qualityText, "2160p · 1080p · 720p · 480p")
    }

    func testBrowserCookieSourceMapping() {
        XCTAssertNil(BrowserCookieSource.off.ytDlpName)
        XCTAssertEqual(BrowserCookieSource.chrome.ytDlpName, "chrome")
        XCTAssertEqual(BrowserCookieSource.safari.ytDlpName, "safari")
    }
}
