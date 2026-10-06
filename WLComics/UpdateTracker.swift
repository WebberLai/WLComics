//
//  UpdateTracker.swift
//  WLComics
//

import Foundation

/// 收藏漫畫的集數追蹤：記錄看過、通知過、最新的集數，判斷有沒有新集數。
/// 本機存在 UserDefaults，同時寫入 iCloud KVS 跨裝置同步。只在 main thread 呼叫。
class UpdateTracker: NSObject {

    /// 追蹤資料有變動（含其他裝置同步過來）時發出，畫面與 badge 收到後重新整理
    static let didChangeNotification = Notification.Name("UpdateTrackerDidChange")

    private static let storeKey = "episode_tracking"
    /// 上次完整檢查的時間只存本機，每台裝置各自節流
    private static let lastFullCheckKey = "episode_tracking_last_full_check"

    private static let cloudStore = NSUbiquitousKeyValueStore.default

    private typealias Store = [String: [String: Any]]

    private struct Entry {
        var seen: Int
        var notified: Int
        var latest: Int
        var checkedAt: TimeInterval

        /// 第一次追蹤：三個數字都以目前集數為基準，不顯示 NEW 也不通知
        init(count: Int) {
            seen = count
            notified = count
            latest = count
            checkedAt = Date().timeIntervalSince1970
        }

        init?(_ dict: [String: Any]?) {
            guard let dict = dict,
                  let seen = dict["seen_count"] as? Int,
                  let notified = dict["notified_count"] as? Int,
                  let latest = dict["latest_count"] as? Int else { return nil }
            self.seen = seen
            self.notified = notified
            self.latest = latest
            checkedAt = dict["checked_at"] as? TimeInterval ?? 0
        }

        var dictionary: [String: Any] {
            return ["seen_count": seen,
                    "notified_count": notified,
                    "latest_count": latest,
                    "checked_at": checkedAt]
        }
    }

    // MARK: - 查詢

    static var lastFullCheckAt: Date? {
        get { return UserDefaults.standard.object(forKey: lastFullCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastFullCheckKey) }
    }

    static func hasUpdate(comicId: String) -> Bool {
        guard let entry = Entry(loadLocal()[comicId]) else { return false }
        return entry.latest > entry.seen
    }

    /// 收藏中有新集數的部數，給分頁與 App 圖示 badge 用
    static func updatedComicCount() -> Int {
        let store = loadLocal()
        return Set(favoriteIds()).filter { id in
            guard let entry = Entry(store[id]) else { return false }
            return entry.latest > entry.seen
        }.count
    }

    /// 有新集數但還沒通知過的收藏，依收藏順序
    static func pendingNotificationIds() -> [String] {
        let store = loadLocal()
        return favoriteIds().filter { id in
            guard let entry = Entry(store[id]) else { return false }
            return entry.latest > entry.notified
        }
    }

    // MARK: - 寫入

    /// 檢查成功抓到集數時呼叫。0 集代表解析失敗，不更新
    static func recordCheck(comicId: String, episodeCount: Int) {
        guard episodeCount > 0 else { return }
        var store = loadLocal()
        store[comicId] = applying(count: episodeCount, to: Entry(store[comicId])).dictionary
        commit(store)
    }

    /// 使用者進入集數列表（線上載入成功）時呼叫：NEW 消失，也不需要再通知
    static func markSeen(comicId: String, episodeCount: Int) {
        guard episodeCount > 0 else { return }
        var store = loadLocal()
        var entry = applying(count: episodeCount, to: Entry(store[comicId]))
        entry.seen = entry.latest
        entry.notified = max(entry.notified, entry.latest)
        store[comicId] = entry.dictionary
        commit(store)
    }

    static func markNotified(comicIds: [String]) {
        var store = loadLocal()
        var changed = false
        for id in comicIds {
            guard var entry = Entry(store[id]), entry.notified < entry.latest else { continue }
            entry.notified = entry.latest
            store[id] = entry.dictionary
            changed = true
        }
        if changed { commit(store) }
    }

    /// 移除已不在收藏中的漫畫，避免 KVS 無限成長
    static func prune(keeping comicIds: Set<String>) {
        let store = loadLocal()
        let kept = store.filter { comicIds.contains($0.key) }
        if kept.count != store.count { commit(kept) }
    }

    /// 第一次追蹤，或網站刪了集數（集數變少）時，三個數字都重設為目前集數
    private static func applying(count: Int, to old: Entry?) -> Entry {
        guard var entry = old, count >= entry.latest else { return Entry(count: count) }
        entry.latest = count
        entry.checkedAt = Date().timeIntervalSince1970
        return entry
    }

    private static func commit(_ store: Store) {
        saveLocal(store)
        cloudStore.set(store, forKey: storeKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static func favoriteIds() -> [String] {
        return FavoriteComics.listAllFavorite().compactMap { $0.object(forKey: "comic_id") as? String }
    }

    // MARK: - iCloud 同步

    /// 在 app 啟動時呼叫一次
    static func startCloudSync() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloudStore, queue: .main) { note in
            // 同一個 KVS 也存了收藏與閱讀進度，只處理這個 key
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard changedKeys.contains(storeKey) else { return }
            mergeFromCloud()
        }
        cloudStore.synchronize()
        mergeFromCloud()
    }

    /// 每部漫畫：seen、notified 取較大值（任一台看過或通知過就算），latest 取較新檢查的那筆
    private static func mergeFromCloud() {
        let cloud = cloudStore.dictionary(forKey: storeKey) as? Store ?? [:]
        let local = loadLocal()

        var merged = local
        for (comicId, cloudDict) in cloud {
            guard let cloudEntry = Entry(cloudDict) else { continue }
            guard let localEntry = Entry(local[comicId]) else {
                merged[comicId] = cloudDict
                continue
            }
            var entry = cloudEntry.checkedAt > localEntry.checkedAt ? cloudEntry : localEntry
            // 不能超過 latest：另一台因集數變少而重設基準時，取 max 會讓之後補回的集數永遠不顯示 NEW
            entry.seen = min(max(cloudEntry.seen, localEntry.seen), entry.latest)
            entry.notified = min(max(cloudEntry.notified, localEntry.notified), entry.latest)
            merged[comicId] = entry.dictionary
        }

        let mergedDict = NSDictionary(dictionary: merged)
        if !mergedDict.isEqual(to: local) {
            saveLocal(merged)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
        if !mergedDict.isEqual(to: cloud) {
            cloudStore.set(merged, forKey: storeKey)
        }
    }

    // MARK: - 本機儲存

    private static func loadLocal() -> Store {
        return UserDefaults.standard.dictionary(forKey: storeKey) as? Store ?? [:]
    }

    private static func saveLocal(_ store: Store) {
        UserDefaults.standard.set(store, forKey: storeKey)
    }

    // MARK: - 除錯

    #if DEBUG
    /// 模擬「網站多了一集」：seen、notified 各減 1，並清掉上次檢查時間讓背景檢查不被節流
    /// 用法（lldb）：po UpdateTracker.debugRewind(comicId: "103")
    static func debugRewind(comicId: String) {
        var store = loadLocal()
        guard var entry = Entry(store[comicId]) else {
            print("UpdateTracker: \(comicId) 沒有追蹤資料，先下拉檢查一次")
            return
        }
        entry.seen = max(0, entry.seen - 1)
        entry.notified = max(0, entry.notified - 1)
        store[comicId] = entry.dictionary
        lastFullCheckAt = nil
        commit(store)
    }

    /// 列出所有收藏的追蹤資料，方便找 comicId
    /// 用法（lldb）：po UpdateTracker.debugDump()
    static func debugDump() {
        let store = loadLocal()
        for favorite in FavoriteComics.listAllFavorite() {
            let id = favorite.object(forKey: "comic_id") as? String ?? "?"
            let name = favorite.object(forKey: "name") as? String ?? "?"
            if let entry = Entry(store[id]) {
                print("\(id) \(name) seen=\(entry.seen) notified=\(entry.notified) latest=\(entry.latest)")
            } else {
                print("\(id) \(name) 尚未追蹤")
            }
        }
        print("lastFullCheckAt=\(String(describing: lastFullCheckAt))")
    }
    #endif
}
