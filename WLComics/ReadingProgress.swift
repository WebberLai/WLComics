//
//  ReadingProgress.swift
//  WLComics
//

import Foundation

/// 每部漫畫的閱讀進度（最後看的集數與頁碼）。
/// 本機存在 UserDefaults，同時寫入 iCloud KVS 跨裝置同步；合併時每部漫畫取較新的那筆。
class ReadingProgress: NSObject {

    struct Entry {
        let episodeUrl: String
        let episodeName: String
        let page: Int
        let updatedAt: TimeInterval
    }

    /// 進度有變動（含其他裝置同步過來）時發出，畫面收到後重新整理
    static let didChangeNotification = Notification.Name("ReadingProgressDidChange")

    private static let storeKey = "reading_progress"
    /// KVS 單一 key 上限 1MB，只保留最近的幾百部，避免無限成長
    private static let maxEntries = 500

    private static let cloudStore = NSUbiquitousKeyValueStore.default

    private typealias Store = [String: [String: Any]]

    // MARK: - 讀寫

    /// 集數網址在載入前是相對路徑，載入後會被補成 https://www.8comic.com/view/...，
    /// 比對與儲存前統一去掉前綴，兩種寫法才會視為同一集
    static func normalizedEpisodeUrl(_ url: String) -> String {
        if let range = url.range(of: "/view/") {
            return String(url[range.upperBound...])
        }
        return url
    }

    static func progress(for comicId: String) -> Entry? {
        guard let dict = loadLocal()[comicId],
              let url = dict["episode_url"] as? String,
              let page = dict["page"] as? Int else { return nil }
        return Entry(episodeUrl: url,
                     episodeName: dict["episode_name"] as? String ?? "",
                     page: page,
                     updatedAt: dict["updated_at"] as? TimeInterval ?? 0)
    }

    static func save(comicId: String, episodeUrl rawUrl: String, episodeName: String, page: Int) {
        let episodeUrl = normalizedEpisodeUrl(rawUrl)
        var store = loadLocal()
        // 同一集同一頁就不重寫，layout 重算時常會重複回報
        if let old = store[comicId],
           old["episode_url"] as? String == episodeUrl,
           old["page"] as? Int == page {
            return
        }
        store[comicId] = ["episode_url": episodeUrl,
                          "episode_name": episodeName,
                          "page": page,
                          "updated_at": Date().timeIntervalSince1970]
        store = trimmed(store)
        saveLocal(store)
        cloudStore.set(store, forKey: storeKey)
    }

    // MARK: - iCloud 同步

    /// 在 app 啟動時呼叫一次
    static func startCloudSync() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloudStore, queue: .main) { note in
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard changedKeys.contains(storeKey) else { return }
            mergeFromCloud()
        }
        cloudStore.synchronize()
        mergeFromCloud()
    }

    /// 每部漫畫取 updated_at 較新的那筆；本機有較新的資料時推回雲端
    private static func mergeFromCloud() {
        let cloud = cloudStore.dictionary(forKey: storeKey) as? Store ?? [:]
        let local = loadLocal()

        var merged = local
        var localChanged = false
        var cloudNeedsUpdate = false
        for (comicId, cloudEntry) in cloud {
            let cloudTime = cloudEntry["updated_at"] as? TimeInterval ?? 0
            let localTime = local[comicId]?["updated_at"] as? TimeInterval ?? -1
            if cloudTime > localTime {
                merged[comicId] = cloudEntry
                localChanged = true
            }
        }
        for (comicId, localEntry) in local {
            let localTime = localEntry["updated_at"] as? TimeInterval ?? 0
            let cloudTime = cloud[comicId]?["updated_at"] as? TimeInterval ?? -1
            if localTime > cloudTime { cloudNeedsUpdate = true }
        }

        merged = trimmed(merged)
        if localChanged {
            saveLocal(merged)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
        if cloudNeedsUpdate {
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

    /// 超過上限時丟掉最久沒看的
    private static func trimmed(_ store: Store) -> Store {
        guard store.count > maxEntries else { return store }
        let sorted = store.sorted {
            ($0.value["updated_at"] as? TimeInterval ?? 0) > ($1.value["updated_at"] as? TimeInterval ?? 0)
        }
        return Dictionary(uniqueKeysWithValues: sorted.prefix(maxEntries).map { ($0.key, $0.value) })
    }
}
