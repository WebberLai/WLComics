//
//  SDKParserTests.swift
//  WLComicsTests
//
//  Comic8SDK 的解析測試，用存下來的 8comic 網頁（Fixtures/，2026-10-07 抓的海賊王）。
//  改 WLComics/Comic8SDK 的 Parser / JSnview 後跑這組，確認沒有改壞。
//

import XCTest
@testable import WLComics

final class SDKParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: SDKParserTests.self)
        let url = bundle.url(forResource: name, withExtension: "html")
            ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")
        let data = try Data(contentsOf: XCTUnwrap(url, "找不到測試資料 \(name).html"))
        // 與 R8Comic 下載後的解碼方式相同
        return StringUtility.dataToStringBig5(data: data)
    }

    private func parseComicDetail() throws -> Comic {
        // Comic 的 init 不是 public，用 SDK 提供的方式建立
        let comic = R8Comic.get().generatorFakeComic("103", name: "海賊王")
        return Parser().comicDetail(htmlString: try fixture("comic-detail-103"), comic: comic)
    }

    // MARK: - 集數列表

    func testComicDetailParsesEpisodes() throws {
        let episodes = try parseComicDetail().getEpisode()
        XCTAssertEqual(episodes.count, 792)

        let first = try XCTUnwrap(episodes.first)
        XCTAssertEqual(first.getName(), "1卷")
        XCTAssertEqual(first.getUrl(), "103.html?ch=1")
        XCTAssertEqual(first.getCatid(), "6")
        XCTAssertEqual(first.getCopyright(), "1")

        let last = try XCTUnwrap(episodes.last)
        XCTAssertEqual(last.getName(), "1194話 萬事皆會變")
        XCTAssertEqual(last.getUrl(), "103.html?ch=1194")
    }

    func testEpisodeNamesHaveNoTagsOrLineBreaks() throws {
        for episode in try parseComicDetail().getEpisode() {
            let name = episode.getName()
            XCTAssertFalse(name.isEmpty)
            XCTAssertNil(name.rangeOfCharacter(from: CharacterSet(charactersIn: "<>\r\n\t")), name)
        }
    }

    // MARK: - 漫畫資訊

    func testComicDetailParsesInfo() throws {
        let comic = try parseComicDetail()
        XCTAssertEqual(comic.getAuthor(), "尾田榮一郎")
        XCTAssertEqual(comic.getLatestUpdateDateTime(), "2026-09-27")
        let description = try XCTUnwrap(comic.getDescription())
        XCTAssertTrue(description.hasPrefix("他擁有世上一切財富"), description)
        XCTAssertNil(description.rangeOfCharacter(from: CharacterSet(charactersIn: "<>\r\n")))
    }

    // MARK: - 編碼

    /// 網站已是 UTF-8，要直接以 UTF-8 解出正確的中文
    func testUtf8PageDecodesCorrectly() {
        let data = Data("<li>海賊王</li>".utf8)
        XCTAssertEqual(StringUtility.dataToStringBig5(data: data), "<li>海賊王</li>")
    }

    /// 舊網頁（Big5）不是合法 UTF-8，要改用 Big5 解碼
    func testBig5PageFallsBack() throws {
        let big5 = try XCTUnwrap("海賊王".data(using: String.Encoding(rawValue: StringUtility.ENCODE_BIG5)))
        XCTAssertNil(String(data: big5, encoding: .utf8))
        XCTAssertEqual(StringUtility.dataToStringBig5(data: big5), "海賊王")
    }

    // MARK: - 單集圖片網址

    func testEpisodePageUrls() throws {
        let episode = try XCTUnwrap(parseComicDetail().getEpisode().first)
        _ = Parser().episodeDetail(try fixture("episode-view-103-ch1"), episode: episode)
        episode.setUpPages()

        let urls = episode.getImageUrlList()
        XCTAssertEqual(urls.count, 104)
        XCTAssertEqual(urls.first, "https://img9.8comic.com/4/103/1/001_8a7.jpg")
        XCTAssertEqual(urls.last, "https://img9.8comic.com/4/103/1/104_vvw.jpg")
        for url in urls {
            XCTAssertTrue(url.hasPrefix("https://"), url)
            XCTAssertTrue(url.hasSuffix(".jpg"), url)
        }
    }

    func testEpisodeWithoutSourceReturnsNoPages() {
        let episode = Episode()
        episode.setCh("1")
        _ = Parser().episodeDetail("<html>改版後找不到圖片的網頁</html>", episode: episode)
        episode.setUpPages()
        XCTAssertEqual(episode.getPages(), 0)
    }

    // MARK: - 小工具

    /// comicDetail 以 "\n" 切行，每行尾端只會剩 "\r"
    /// （Swift 把 "\r\n" 視為一個字元，replaceTag 不會拿掉完整的 CRLF）
    func testReplaceTagStripsTagsAndCarriageReturn() {
        XCTAssertEqual(Parser().replaceTag("<b>第1話</b>\r"), "第1話")
        XCTAssertEqual(Parser().replaceTag("<a href='#'>1卷</a>"), "1卷")
    }
}

/// 連線到真正的 8comic 網站，確認網站沒有改版。預設跳過：
/// 在 scheme 的 Test → Arguments → Environment Variables 加上 WLCOMICS_LIVE_TESTS = 1 才會跑。
final class SDKLiveSiteTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WLCOMICS_LIVE_TESTS"] == "1",
                          "設定 WLCOMICS_LIVE_TESTS=1 才會連線測試")
    }

    private func fetch(_ urlString: String) throws -> String {
        let done = expectation(description: urlString)
        var result: Data?
        URLSession.shared.dataTask(with: try XCTUnwrap(URL(string: urlString))) { data, _, _ in
            result = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        return StringUtility.dataToStringBig5(data: try XCTUnwrap(result, "下載失敗：\(urlString)"))
    }

    func testLiveComicAndEpisodeStillParse() throws {
        let r8comic = R8Comic.get()
        let comic = r8comic.generatorFakeComic("103", name: "海賊王")
        let detail = Parser().comicDetail(htmlString: try fetch(r8comic.getConfig().getComicDetailUrl("103")), comic: comic)
        XCTAssertNotNil(detail.getLatestUpdateDateTime(), "更新日期解析不到，網站可能改版")
        let episode = try XCTUnwrap(detail.getEpisode().first, "集數列表解析不到任何集數，網站可能改版")

        let html = try fetch(Config.mComicHost + "view/" + episode.getUrl())
        _ = Parser().episodeDetail(html, episode: episode)
        episode.setUpPages()
        XCTAssertGreaterThan(episode.getPages(), 0, "圖片網址解析不到，網站可能改版")
    }
}
