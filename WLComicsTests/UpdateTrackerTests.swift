//
//  UpdateTrackerTests.swift
//  WLComicsTests
//
//  只測計算用的純函式，不讀寫 UserDefaults / iCloud
//

import XCTest
@testable import WLComics

final class UpdateTrackerTests: XCTestCase {

    private typealias Entry = UpdateTracker.Entry

    private func dict(seen: Int, notified: Int, latest: Int, checkedAt: TimeInterval) -> [String: Any] {
        return ["seen_count": seen, "notified_count": notified, "latest_count": latest, "checked_at": checkedAt]
    }

    private func entry(seen: Int, notified: Int, latest: Int, checkedAt: TimeInterval = 100) -> Entry {
        return Entry(dict(seen: seen, notified: notified, latest: latest, checkedAt: checkedAt))!
    }

    // MARK: - applying

    func testFirstCheckSetsBaselineWithoutUpdate() {
        let result = UpdateTracker.applying(count: 10, to: nil)
        XCTAssertEqual([result.seen, result.notified, result.latest], [10, 10, 10])
        XCTAssertFalse(result.hasUpdate)
        XCTAssertFalse(result.needsNotification)
    }

    func testMoreEpisodesShowsUpdateAndNeedsNotification() {
        let result = UpdateTracker.applying(count: 12, to: entry(seen: 10, notified: 10, latest: 10))
        XCTAssertEqual([result.seen, result.notified, result.latest], [10, 10, 12])
        XCTAssertTrue(result.hasUpdate)
        XCTAssertTrue(result.needsNotification)
    }

    func testSameCountKeepsState() {
        let result = UpdateTracker.applying(count: 12, to: entry(seen: 10, notified: 12, latest: 12))
        XCTAssertEqual([result.seen, result.notified, result.latest], [10, 12, 12])
    }

    /// 網站刪了集數：重設基準，不顯示 NEW
    func testFewerEpisodesResetsBaseline() {
        let result = UpdateTracker.applying(count: 8, to: entry(seen: 10, notified: 10, latest: 12))
        XCTAssertEqual([result.seen, result.notified, result.latest], [8, 8, 8])
        XCTAssertFalse(result.hasUpdate)
    }

    // MARK: - markingSeen / markingNotified

    func testMarkingSeenClearsUpdateAndNotification() {
        let result = UpdateTracker.markingSeen(entry(seen: 10, notified: 10, latest: 12), count: 13)
        XCTAssertEqual([result.seen, result.notified, result.latest], [13, 13, 13])
        XCTAssertFalse(result.hasUpdate)
        XCTAssertFalse(result.needsNotification)
    }

    func testMarkingSeenOnUntrackedComicSetsBaseline() {
        let result = UpdateTracker.markingSeen(nil, count: 5)
        XCTAssertEqual([result.seen, result.notified, result.latest], [5, 5, 5])
    }

    /// 通知過後 NEW 仍要顯示，直到使用者進入集數列表
    func testMarkingNotifiedKeepsNewLabel() {
        let result = UpdateTracker.markingNotified(entry(seen: 10, notified: 10, latest: 12))
        XCTAssertEqual(result?.notified, 12)
        XCTAssertEqual(result?.hasUpdate, true)
        XCTAssertEqual(result?.needsNotification, false)
    }

    func testMarkingNotifiedReturnsNilWhenAlreadyNotified() {
        XCTAssertNil(UpdateTracker.markingNotified(entry(seen: 10, notified: 12, latest: 12)))
    }

    // MARK: - merged

    func testMergeAddsCloudOnlyAndKeepsLocalOnly() {
        let local = ["1": dict(seen: 1, notified: 1, latest: 1, checkedAt: 100)]
        let cloud = ["2": dict(seen: 2, notified: 2, latest: 2, checkedAt: 100)]
        let merged = UpdateTracker.merged(local: local, cloud: cloud)
        XCTAssertEqual(Set(merged.keys), ["1", "2"])
    }

    /// latest 取較新檢查的那筆；seen、notified 任一台有就算
    func testMergeTakesNewerLatestAndMaxSeen() {
        let local = ["1": dict(seen: 12, notified: 12, latest: 12, checkedAt: 100)]
        let cloud = ["1": dict(seen: 10, notified: 13, latest: 14, checkedAt: 200)]
        let result = Entry(UpdateTracker.merged(local: local, cloud: cloud)["1"])!
        XCTAssertEqual([result.seen, result.notified, result.latest], [12, 13, 14])
        XCTAssertEqual(result.checkedAt, 200)
    }

    /// 另一台因集數變少重設基準時，seen、notified 不能超過 latest
    func testMergeClampsToLatestAfterReset() {
        let local = ["1": dict(seen: 12, notified: 12, latest: 12, checkedAt: 100)]
        let cloud = ["1": dict(seen: 8, notified: 8, latest: 8, checkedAt: 200)]
        let result = Entry(UpdateTracker.merged(local: local, cloud: cloud)["1"])!
        XCTAssertEqual([result.seen, result.notified, result.latest], [8, 8, 8])

        // 之後補回集數要能顯示 NEW
        let next = UpdateTracker.applying(count: 9, to: result)
        XCTAssertTrue(next.hasUpdate)
    }

    func testMergeIgnoresInvalidCloudEntry() {
        let local = ["1": dict(seen: 1, notified: 1, latest: 1, checkedAt: 100)]
        let cloud: UpdateTracker.Store = ["1": ["seen_count": "壞掉的資料"], "2": [:]]
        let merged = UpdateTracker.merged(local: local, cloud: cloud)
        XCTAssertEqual(Set(merged.keys), ["1"])
        XCTAssertEqual(Entry(merged["1"])?.latest, 1)
    }
}
