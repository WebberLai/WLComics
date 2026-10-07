//
//  ReadingModeStore.swift
//  WLComics
//

import Foundation

/// 閱讀模式：左右翻頁（日漫）或上下捲動（條漫）
enum ReadingMode: String {
    case horizontal
    case vertical
}

/// 每部漫畫手動選擇的閱讀模式。本機存在 UserDefaults，同時寫入 iCloud KVS 跨裝置同步。
/// 只在 main thread 呼叫。
class ReadingModeStore: NSObject {

    private static let storeKey = "reading_mode"
    /// KVS 單一 key 上限 1MB，每部漫畫一筆，只保留最近的一千部
    private static let maxEntries = 1000

    private static let sourceManual = "manual"

    private static let cloudStore = NSUbiquitousKeyValueStore.default

    private typealias Store = [String: [String: Any]]

    // MARK: - 讀寫

    /// 沒有手動選過時回傳 nil，由閱讀器用預設的左右翻頁。
    /// 早期版本曾存過自動判斷（source = auto）的結果，判斷不準，一律忽略
    static func mode(for comicId: String) -> ReadingMode? {
        guard let entry = loadLocal()[comicId],
              entry["source"] as? String == sourceManual,
              let raw = entry["mode"] as? String else { return nil }
        return ReadingMode(rawValue: raw)
    }

    static func setManual(_ mode: ReadingMode, for comicId: String) {
        save(mode, source: sourceManual, for: comicId)
    }

    private static func save(_ mode: ReadingMode, source: String, for comicId: String) {
        var store = loadLocal()
        store[comicId] = ["mode": mode.rawValue,
                          "source": source,
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
            // 同一個 KVS 也存了其他資料，只處理這個 key
            let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard changedKeys.contains(storeKey) else { return }
            mergeFromCloud()
        }
        cloudStore.synchronize()
        mergeFromCloud()
    }

    /// a 是否應該蓋過 b：手動優先，來源相同時取較新的
    private static func entry(_ a: [String: Any], winsOver b: [String: Any]?) -> Bool {
        guard let b = b else { return true }
        let aManual = a["source"] as? String == sourceManual
        let bManual = b["source"] as? String == sourceManual
        if aManual != bManual { return aManual }
        return (a["updated_at"] as? TimeInterval ?? 0) > (b["updated_at"] as? TimeInterval ?? 0)
    }

    private static func mergeFromCloud() {
        let cloud = cloudStore.dictionary(forKey: storeKey) as? Store ?? [:]
        let local = loadLocal()

        var merged = local
        var localChanged = false
        for (comicId, cloudEntry) in cloud where entry(cloudEntry, winsOver: local[comicId]) {
            merged[comicId] = cloudEntry
            localChanged = true
        }
        let cloudNeedsUpdate = local.contains { comicId, localEntry in
            entry(localEntry, winsOver: cloud[comicId])
        }

        merged = trimmed(merged)
        if localChanged {
            saveLocal(merged)
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

    /// 超過上限時丟掉最久沒更新的
    private static func trimmed(_ store: Store) -> Store {
        guard store.count > maxEntries else { return store }
        let sorted = store.sorted {
            ($0.value["updated_at"] as? TimeInterval ?? 0) > ($1.value["updated_at"] as? TimeInterval ?? 0)
        }
        return Dictionary(uniqueKeysWithValues: sorted.prefix(maxEntries).map { ($0.key, $0.value) })
    }
}
