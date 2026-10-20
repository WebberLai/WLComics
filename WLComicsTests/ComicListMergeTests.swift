//
//  ComicListMergeTests.swift
//  WLComicsTests
//
//  App 更新時 AllComics.plist 的合併邏輯，只測純函式，不讀寫檔案
//

import XCTest
@testable import WLComics

final class ComicListMergeTests: XCTestCase {

    private func entry(_ id: String, _ name: String) -> [String: String] {
        return ["comic_id": id, "name": name]
    }

    func testKeepsSavedComicsMissingFromBundle() {
        let bundle = [entry("1", "A"), entry("2", "B")]
        let saved = [entry("1", "A"), entry("99", "搜尋補進來的")]
        let merged = AppDelegate.mergedComicEntries(bundle: bundle, saved: saved)
        XCTAssertEqual(merged.compactMap { $0["comic_id"] }, ["1", "2", "99"])
    }

    /// 同一部漫畫以 bundle 的名稱為準
    func testBundleNameWins() {
        let merged = AppDelegate.mergedComicEntries(bundle: [entry("1", "新名稱")], saved: [entry("1", "舊名稱")])
        XCTAssertEqual(merged, [entry("1", "新名稱")])
    }

    func testSkipsInvalidAndDuplicateSavedEntries() {
        let saved = [["comic_id": "5"], ["name": "沒有 id"], entry("6", "C"), entry("6", "C")]
        let merged = AppDelegate.mergedComicEntries(bundle: [], saved: saved)
        XCTAssertEqual(merged, [entry("6", "C")])
    }
}
