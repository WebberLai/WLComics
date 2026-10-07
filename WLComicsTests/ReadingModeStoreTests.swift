//
//  ReadingModeStoreTests.swift
//  WLComicsTests
//
//  只測計算用的純函式，不讀寫 UserDefaults / iCloud
//

import XCTest
@testable import WLComics

final class ReadingModeStoreTests: XCTestCase {

    private func entry(_ mode: ReadingMode, source: String = "manual", at time: TimeInterval) -> [String: Any] {
        return ["mode": mode.rawValue, "source": source, "updated_at": time]
    }

    // MARK: - mode(in:for:)

    func testManualEntryIsUsed() {
        let store = ["1": entry(.vertical, at: 100)]
        XCTAssertEqual(ReadingModeStore.mode(in: store, for: "1"), .vertical)
    }

    /// 早期存下的自動判斷結果一律忽略
    func testAutoEntryIsIgnored() {
        let store = ["1": entry(.vertical, source: "auto", at: 100)]
        XCTAssertNil(ReadingModeStore.mode(in: store, for: "1"))
    }

    func testMissingOrInvalidEntryReturnsNil() {
        let store: ReadingModeStore.Store = ["2": ["mode": "diagonal", "source": "manual", "updated_at": 100.0]]
        XCTAssertNil(ReadingModeStore.mode(in: store, for: "1"))
        XCTAssertNil(ReadingModeStore.mode(in: store, for: "2"))
    }

    // MARK: - entry(_:winsOver:)

    func testManualWinsOverNewerAuto() {
        XCTAssertTrue(ReadingModeStore.entry(entry(.vertical, at: 100),
                                             winsOver: entry(.horizontal, source: "auto", at: 999)))
        XCTAssertFalse(ReadingModeStore.entry(entry(.horizontal, source: "auto", at: 999),
                                              winsOver: entry(.vertical, at: 100)))
    }

    func testSameSourceNewerWins() {
        XCTAssertTrue(ReadingModeStore.entry(entry(.vertical, at: 200), winsOver: entry(.horizontal, at: 100)))
        XCTAssertFalse(ReadingModeStore.entry(entry(.vertical, at: 100), winsOver: entry(.horizontal, at: 200)))
        XCTAssertFalse(ReadingModeStore.entry(entry(.vertical, at: 100), winsOver: entry(.vertical, at: 100)))
    }

    func testAnythingWinsOverMissing() {
        XCTAssertTrue(ReadingModeStore.entry(entry(.horizontal, source: "auto", at: 0), winsOver: nil))
    }

    // MARK: - merged

    func testNewerCloudReplacesLocal() {
        let local = ["1": entry(.horizontal, at: 100)]
        let cloud = ["1": entry(.vertical, at: 200)]
        let result = ReadingModeStore.merged(local: local, cloud: cloud)
        XCTAssertEqual(ReadingModeStore.mode(in: result.store, for: "1"), .vertical)
        XCTAssertTrue(result.localChanged)
        XCTAssertFalse(result.cloudNeedsUpdate)
    }

    func testNewerLocalIsPushedToCloud() {
        let local = ["1": entry(.vertical, at: 200), "2": entry(.vertical, at: 100)]
        let cloud = ["1": entry(.horizontal, at: 100)]
        let result = ReadingModeStore.merged(local: local, cloud: cloud)
        XCTAssertEqual(ReadingModeStore.mode(in: result.store, for: "1"), .vertical)
        XCTAssertFalse(result.localChanged)
        XCTAssertTrue(result.cloudNeedsUpdate)
    }

    func testIdenticalStoresChangeNothing() {
        let store = ["1": entry(.vertical, at: 100)]
        let result = ReadingModeStore.merged(local: store, cloud: store)
        XCTAssertFalse(result.localChanged)
        XCTAssertFalse(result.cloudNeedsUpdate)
    }

    // MARK: - trimmed

    func testTrimDropsOldestEntries() {
        var store = ReadingModeStore.Store()
        for i in 0...ReadingModeStore.maxEntries {
            store["\(i)"] = entry(.vertical, at: TimeInterval(i))
        }
        let trimmed = ReadingModeStore.trimmed(store)
        XCTAssertEqual(trimmed.count, ReadingModeStore.maxEntries)
        XCTAssertNil(trimmed["0"])
        XCTAssertNotNil(trimmed["\(ReadingModeStore.maxEntries)"])
    }
}
