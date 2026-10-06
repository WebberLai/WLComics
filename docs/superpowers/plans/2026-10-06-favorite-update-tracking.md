# 收藏漫畫追更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 追蹤「我的收藏」漫畫的新集數，在收藏列表、分頁與 App 圖示上標示，並每天在背景檢查一次、發本地通知。

**Architecture:** 新增三個檔案：`UpdateTracker`（存資料並同步 iCloud，寫法比照 `ReadingProgress`）、`UpdateChecker`（向網站抓集數並比對）、`UpdateNotifier`（本地通知與 badge）。既有的 `AppDelegate`、`SceneDelegate`、收藏頁、集數頁、漫畫列表只加上呼叫點。所有追蹤相關的程式只在 main thread 執行。

**Tech Stack:** Swift 5、UIKit、BackgroundTasks（`BGAppRefreshTask`）、UserNotifications、`NSUbiquitousKeyValueStore`、Swift8ComicSDK（`loadComicDetail`）、SVProgressHUD。

**Spec:** `docs/superpowers/specs/2026-10-06-favorite-update-tracking-design.md`

## Global Constraints

- 最低版本 iOS 14.0；iOS 16 以上才有的 API 要用 `#available` 包起來。
- 只追蹤收藏（`FavoriteComics.listAllFavorite()`）中的漫畫。
- 背景與前景檢查間隔：24 小時（`24 * 60 * 60`）；下拉不受限制。
- 單部請求 timeout：20 秒；同時最多 2 個請求。
- iCloud KVS key：`episode_tracking`；本機上次完整檢查時間 key：`episode_tracking_last_full_check`（不同步）。
- 背景任務 ID：`com.webberlai.WLComics.checkUpdates`，程式以 `Bundle.main.bundleIdentifier + ".checkUpdates"` 組出；Info.plist 用 `$(PRODUCT_BUNDLE_IDENTIFIER).checkUpdates`。
- 通知：3 部以內每部一則，超過 3 部合併成一則；只有背景檢查會發通知。
- 通知權限：`.alert`、`.sound`、`.badge`。
- 所有 UI 文字使用台灣繁體中文；收藏分頁在 storyboard 中的標題是「我的收藏」。
- 不改變收藏列表既有的拼音分區排序。
- 專案沒有 test target。每個任務的驗證方式是：交給使用者在 Xcode build（不要自行執行 `xcodebuild`），再依步驟手動驗證。
- 使用者自己 commit；任務結束時不要 commit，只列出改動的檔案。
- 新增 `.swift` 檔要手動加進 `WLComics.xcodeproj/project.pbxproj` 的 WLComics target（`WLMacComic` target 不要動）。

## Review Focus

1. **網站暫時壞掉或解析出 0 集**：不可以把基準重設成 0，否則修好後所有收藏一次跳出 NEW 和通知。→ Task 1 的 `recordCheck` / `markSeen` 遇到 0 直接 return；Task 2 把 0 集當失敗。驗證：Task 4 的步驟 5（斷網下拉）。
2. **兩台裝置同時改動**：iPhone 看過、iPad 還沒同步時，合併後不可讓 NEW 重新出現。→ Task 1 的 `mergeFromCloud` 對 `seen` / `notified` 取 max。驗證：Task 4 的步驟 6。
3. **檢查進行中又觸發**（回到前景的同時下拉）：不可發出兩輪請求，兩邊的 completion 都要被呼叫，下拉的轉圈才會收起。→ Task 2 的 `completions` 陣列與 `isRunning`。驗證：Task 4 的步驟 4。
4. **背景任務被系統中止**：必須呼叫 `setTaskCompleted`，否則系統會降低 App 之後的背景執行機會。→ Task 2 的 `cancel()` 會立刻 `finish`；Task 5 的 expirationHandler。驗證：Task 5 的步驟 4。
5. **取消收藏後 badge 數字殘留**：取消收藏後，badge 不可以還算進那一部。→ `updatedComicCount()` 只算目前的收藏，加上 Task 4 在取消收藏處呼叫 `UpdateBadge.refresh()`。驗證：Task 4 的步驟 7。

---

## 檔案結構

| 檔案 | 動作 | 職責 |
|---|---|---|
| `WLComics/UpdateTracker.swift` | 新增 | 每部收藏的 seen / notified / latest 計數、iCloud 合併、上次檢查時間、DEBUG 輔助 |
| `WLComics/UpdateChecker.swift` | 新增 | 節流、併發控制、timeout、呼叫 SDK、產生 `Result` |
| `WLComics/UpdateNotifier.swift` | 新增 | `UpdateNotifier`（權限、發通知）與 `UpdateBadge`（分頁與 App 圖示數字） |
| `WLComics.xcodeproj/project.pbxproj` | 修改 | 把三個新檔加入 WLComics target |
| `WLComics/Info.plist` | 修改 | 背景任務 ID、`UIBackgroundModes` |
| `WLComics/AppDelegate.swift` | 修改 | 啟動同步、註冊與排程背景任務、通知 delegate |
| `WLComics/SceneDelegate.swift` | 修改 | 前景檢查、badge 觀察者、切到收藏分頁 |
| `WLComics/View Controllers/Custom Comic Cell/ComicTableViewCell.swift` | 修改 | NEW 標籤 |
| `WLComics/View Controllers/Left View Controllers/FavoriteTableViewController.swift` | 修改 | 下拉重新整理、顯示 NEW、取消收藏時更新 badge |
| `WLComics/View Controllers/Left View Controllers/ComicEpisodesViewController.swift` | 修改 | 載入集數後 `markSeen` |
| `WLComics/View Controllers/Left View Controllers/MasterViewController.swift` | 修改 | 加入收藏時詢問權限、取消收藏時更新 badge |

---

### Task 1: UpdateTracker（資料與 iCloud 同步）

**Files:**
- Create: `WLComics/UpdateTracker.swift`
- Modify: `WLComics.xcodeproj/project.pbxproj`（加入新檔）
- Modify: `WLComics/AppDelegate.swift:20-22`（啟動同步）

**Interfaces:**
- Consumes: `FavoriteComics.listAllFavorite() -> [NSMutableDictionary]`（key `comic_id`、`name`）
- Produces（皆為 `static`，只在 main thread 呼叫）:
  - `UpdateTracker.didChangeNotification: Notification.Name`
  - `UpdateTracker.lastFullCheckAt: Date?`（可讀寫）
  - `UpdateTracker.hasUpdate(comicId: String) -> Bool`
  - `UpdateTracker.updatedComicCount() -> Int`
  - `UpdateTracker.pendingNotificationIds() -> [String]`
  - `UpdateTracker.recordCheck(comicId: String, episodeCount: Int)`
  - `UpdateTracker.markSeen(comicId: String, episodeCount: Int)`
  - `UpdateTracker.markNotified(comicIds: [String])`
  - `UpdateTracker.prune(keeping: Set<String>)`
  - `UpdateTracker.startCloudSync()`
  - DEBUG only：`UpdateTracker.debugRewind(comicId: String)`、`UpdateTracker.debugDump()`

- [ ] **Step 1: 建立 `WLComics/UpdateTracker.swift`**

```swift
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
            entry.seen = max(cloudEntry.seen, localEntry.seen)
            entry.notified = max(cloudEntry.notified, localEntry.notified)
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
```

- [ ] **Step 2: 把 `UpdateTracker.swift` 加進 project.pbxproj**

在 `/* Begin PBXBuildFile section */` 中，`ReadingProgress.swift in Sources` 那行的下一行加入：

```
		7E1A2B3C4D5E6F7081920A4C /* UpdateTracker.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1A2B3C4D5E6F7081920A4B /* UpdateTracker.swift */; };
```

在 `/* Begin PBXFileReference section */` 中，`ReadingProgress.swift */ = {isa = PBXFileReference` 那行的下一行加入：

```
		7E1A2B3C4D5E6F7081920A4B /* UpdateTracker.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = UpdateTracker.swift; sourceTree = "<group>"; };
```

在 `60A1B90E1F58E2B600E41AAB /* Favorite Model */` group 的 `children` 中，`ReadingProgress.swift */,` 的下一行加入：

```
				7E1A2B3C4D5E6F7081920A4B /* UpdateTracker.swift */,
```

在 `6056EE161F28233F007BBE67 /* Sources */`（WLComics target）的 `files` 中，`ReadingProgress.swift in Sources */,` 的下一行加入：

```
				7E1A2B3C4D5E6F7081920A4C /* UpdateTracker.swift in Sources */,
```

加入前先用 `grep -c 7E1A2B3C4D5E6F7081920A4 WLComics.xcodeproj/project.pbxproj` 確認結果是 0（ID 沒被用過）；加入後應為 4。

- [ ] **Step 3: 在 `AppDelegate` 啟動同步**

`WLComics/AppDelegate.swift` 的 `didFinishLaunchingWithOptions` 中：

```swift
        FavoriteComics.startCloudSync()
        ReadingProgress.startCloudSync()
```

改成：

```swift
        FavoriteComics.startCloudSync()
        ReadingProgress.startCloudSync()
        UpdateTracker.startCloudSync()
```

- [ ] **Step 4: 交給使用者 build**

請使用者在 Xcode 用 WLComics target build（Cmd+B）。
預期：build 成功，沒有新的 warning。App 行為不變（還沒有任何呼叫點）。

---

### Task 2: UpdateChecker（抓網站並比對）

**Files:**
- Create: `WLComics/UpdateChecker.swift`
- Modify: `WLComics.xcodeproj/project.pbxproj`（加入新檔）

**Interfaces:**
- Consumes: Task 1 的 `UpdateTracker.lastFullCheckAt`、`recordCheck(comicId:episodeCount:)`、`pendingNotificationIds()`、`prune(keeping:)`；SDK 的 `R8Comic.loadComicDetail(_:onLoadDetail:)`、`generatorFakeComic(_:name:)`、`Comic.getEpisode()`、`Episode.getName()`
- Produces:
  - `UpdateChecker.shared`
  - `UpdateChecker.Reason`：`.foreground`、`.background`、`.manual`
  - `UpdateChecker.Update`：`comicId: String`、`comicName: String`、`latestEpisodeName: String?`
  - `UpdateChecker.Result`：`updates: [Update]`、`failedCount: Int`、`skipped: Bool`
  - `func check(reason: Reason, completion: @escaping (Result) -> Void)`（main thread 呼叫，completion 在 main thread）
  - `func cancel()`

- [ ] **Step 1: 建立 `WLComics/UpdateChecker.swift`**

```swift
//
//  UpdateChecker.swift
//  WLComics
//

import Foundation
import Swift8ComicSDK

/// 向網站抓收藏漫畫的集數列表，交給 UpdateTracker 比對。只在 main thread 呼叫。
class UpdateChecker {

    enum Reason {
        case foreground
        case background
        /// 下拉重新整理，不受 24 小時限制
        case manual
    }

    struct Update {
        let comicId: String
        let comicName: String
        /// 這次檢查抓到的最新一集名稱；這次沒抓到（之前留下的未通知更新）時為 nil
        let latestEpisodeName: String?
    }

    struct Result {
        /// 有新集數且還沒通知過的收藏
        let updates: [Update]
        let failedCount: Int
        /// 因 24 小時節流而沒有實際檢查
        let skipped: Bool
    }

    static let shared = UpdateChecker()

    private static let minimumInterval: TimeInterval = 24 * 60 * 60
    /// SDK 失敗時不會回呼，自己設 timeout
    private static let requestTimeout: TimeInterval = 20
    /// 一次最多同時抓 2 部，避免對網站造成負擔
    private static let maxConcurrent = 2

    private var completions = [(Result) -> Void]()
    private var isRunning = false
    private var isCancelled = false
    private var favorites = [(id: String, name: String)]()
    private var queue = [(id: String, name: String)]()
    private var inFlight = 0
    private var succeeded = 0
    private var failed = 0
    private var latestEpisodeNames = [String: String]()
    /// 每輪檢查遞增，上一輪遲到的回呼不會影響這一輪
    private var generation = 0

    func check(reason: Reason, completion: @escaping (Result) -> Void) {
        completions.append(completion)
        // 已有檢查在跑：併入同一輪，不重複發請求
        guard !isRunning else { return }

        if reason != .manual, let last = UpdateTracker.lastFullCheckAt,
           Date().timeIntervalSince(last) < UpdateChecker.minimumInterval {
            finish(skipped: true)
            return
        }

        favorites = UpdateChecker.favoriteList()
        queue = favorites
        isRunning = true
        isCancelled = false
        inFlight = 0
        succeeded = 0
        failed = 0
        latestEpisodeNames = [:]
        generation += 1
        launchNext()
    }

    /// 背景任務被系統中止時呼叫：不再發新請求，立刻以目前結果結束
    func cancel() {
        guard isRunning else { return }
        isCancelled = true
        queue.removeAll()
        finish(skipped: false)
    }

    private func launchNext() {
        while inFlight < UpdateChecker.maxConcurrent, !queue.isEmpty {
            let item = queue.removeFirst()
            inFlight += 1
            fetch(item)
        }
        if inFlight == 0 && queue.isEmpty {
            finish(skipped: false)
        }
    }

    private func fetch(_ item: (id: String, name: String)) {
        let round = generation
        var handled = false
        // 正常回呼與 timeout 誰先到就用誰，另一個忽略
        let handle: (Comic?) -> Void = { comic in
            DispatchQueue.main.async {
                guard !handled, round == self.generation, self.isRunning else { return }
                handled = true
                self.inFlight -= 1
                let episodes = comic?.getEpisode() ?? []
                if episodes.isEmpty {
                    // 逾時、網路錯誤，或解析出 0 集（多半是網站改版），都當失敗，不動資料
                    self.failed += 1
                } else {
                    self.succeeded += 1
                    UpdateTracker.recordCheck(comicId: item.id, episodeCount: episodes.count)
                    // 集數依網頁順序由舊到新，最後一集是最新的
                    self.latestEpisodeNames[item.id] = episodes.last?.getName()
                }
                self.launchNext()
            }
        }
        let r8comic = WLComics.sharedInstance().getR8Comic()
        r8comic.loadComicDetail(r8comic.generatorFakeComic(item.id, name: item.name)) { comic in
            handle(comic)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + UpdateChecker.requestTimeout) {
            handle(nil)
        }
    }

    private func finish(skipped: Bool) {
        if !skipped {
            // 全部失敗（例如沒網路）時不記時間，下次回到前景會再試
            if succeeded > 0 {
                UpdateTracker.lastFullCheckAt = Date()
            }
            if !isCancelled {
                UpdateTracker.prune(keeping: Set(favorites.map { $0.id }))
            }
        }

        let names = Dictionary(UpdateChecker.favoriteList().map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        let updates = UpdateTracker.pendingNotificationIds().map { id in
            Update(comicId: id, comicName: names[id] ?? "", latestEpisodeName: latestEpisodeNames[id])
        }
        let result = Result(updates: updates, failedCount: skipped ? 0 : failed, skipped: skipped)

        isRunning = false
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(result) }
    }

    private static func favoriteList() -> [(id: String, name: String)] {
        return FavoriteComics.listAllFavorite().compactMap { dict in
            guard let id = dict.object(forKey: "comic_id") as? String,
                  let name = dict.object(forKey: "name") as? String else { return nil }
            return (id: id, name: name)
        }
    }
}
```

- [ ] **Step 2: 把 `UpdateChecker.swift` 加進 project.pbxproj**

在 PBXBuildFile section 中，Task 1 加入的 `UpdateTracker.swift in Sources` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A5C /* UpdateChecker.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1A2B3C4D5E6F7081920A5B /* UpdateChecker.swift */; };
```

在 PBXFileReference section 中，`UpdateTracker.swift */ = {isa = PBXFileReference` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A5B /* UpdateChecker.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = UpdateChecker.swift; sourceTree = "<group>"; };
```

在 `Favorite Model` group 的 `children` 中，`UpdateTracker.swift */,` 下一行加入：

```
				7E1A2B3C4D5E6F7081920A5B /* UpdateChecker.swift */,
```

在 WLComics target 的 Sources `files` 中，`UpdateTracker.swift in Sources */,` 下一行加入：

```
				7E1A2B3C4D5E6F7081920A5C /* UpdateChecker.swift in Sources */,
```

加入後 `grep -c 7E1A2B3C4D5E6F7081920A5 WLComics.xcodeproj/project.pbxproj` 應為 4。

- [ ] **Step 3: 交給使用者 build**

請使用者 build。
預期：build 成功。App 行為不變。

---

### Task 3: UpdateNotifier 與 UpdateBadge

**Files:**
- Create: `WLComics/UpdateNotifier.swift`
- Modify: `WLComics.xcodeproj/project.pbxproj`（加入新檔）

**Interfaces:**
- Consumes: Task 1 的 `UpdateTracker.updatedComicCount()`、`markNotified(comicIds:)`；Task 2 的 `UpdateChecker.Update`
- Produces:
  - `UpdateNotifier.requestAuthorizationIfNeeded()`
  - `UpdateNotifier.post(_ updates: [UpdateChecker.Update], completion: @escaping () -> Void)`（completion 在 main thread）
  - `UpdateNotifier.identifierPrefix: String`（值 `"update."`，給通知點擊判斷用）
  - `UpdateBadge.favoritesTabItem: UITabBarItem?`（weak，由 SceneDelegate 設定）
  - `UpdateBadge.refresh()`（main thread）

- [ ] **Step 1: 建立 `WLComics/UpdateNotifier.swift`**

```swift
//
//  UpdateNotifier.swift
//  WLComics
//

import UIKit
import UserNotifications

/// 收藏有新集數時發本地通知（只在背景檢查後使用）
enum UpdateNotifier {

    /// 通知 identifier 的前綴，點擊時用來判斷是不是更新通知
    static let identifierPrefix = "update."

    private static let askedKey = "update_notification_permission_asked"
    /// 超過這個數量就合併成一則
    private static let maxIndividual = 3

    /// 第一次需要時詢問通知權限，之後不再問（使用者可到設定自行開啟）
    static func requestAuthorizationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // 剛拿到 badge 權限時，把目前的數字補上 App 圖示
            DispatchQueue.main.async { UpdateBadge.refresh() }
        }
    }

    /// 發出通知並標記為已通知。completion 在 main thread 呼叫
    static func post(_ updates: [UpdateChecker.Update], completion: @escaping () -> Void) {
        guard !updates.isEmpty else {
            completion()
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                requests(for: updates).forEach { center.add($0) }
            }
            DispatchQueue.main.async {
                // 沒有權限也標記，避免日後開啟權限時一次補發舊的更新
                UpdateTracker.markNotified(comicIds: updates.map { $0.comicId })
                completion()
            }
        }
    }

    private static func requests(for updates: [UpdateChecker.Update]) -> [UNNotificationRequest] {
        if updates.count > maxIndividual {
            let content = UNMutableNotificationContent()
            content.title = "收藏有更新"
            content.body = "\(updates.count) 部收藏有更新"
            content.sound = .default
            return [UNNotificationRequest(identifier: identifierPrefix + "summary", content: content, trigger: nil)]
        }
        return updates.map { update in
            let content = UNMutableNotificationContent()
            content.title = update.comicName
            content.body = update.latestEpisodeName.map { "有新集數：\($0)" } ?? "有新集數"
            content.sound = .default
            return UNNotificationRequest(identifier: identifierPrefix + update.comicId, content: content, trigger: nil)
        }
    }
}

/// 「我的收藏」分頁與 App 圖示上的更新部數
enum UpdateBadge {

    /// 由 SceneDelegate 設定；背景啟動沒有畫面時為 nil，只更新 App 圖示
    static weak var favoritesTabItem: UITabBarItem?

    static func refresh() {
        let count = UpdateTracker.updatedComicCount()
        favoritesTabItem?.badgeValue = count > 0 ? "\(count)" : nil
        // 沒有 badge 權限時系統會直接忽略
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
}
```

- [ ] **Step 2: 把 `UpdateNotifier.swift` 加進 project.pbxproj**

在 PBXBuildFile section 中，`UpdateChecker.swift in Sources` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A6C /* UpdateNotifier.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1A2B3C4D5E6F7081920A6B /* UpdateNotifier.swift */; };
```

在 PBXFileReference section 中，`UpdateChecker.swift */ = {isa = PBXFileReference` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A6B /* UpdateNotifier.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = UpdateNotifier.swift; sourceTree = "<group>"; };
```

在 `Favorite Model` group 的 `children` 中，`UpdateChecker.swift */,` 下一行加入：

```
				7E1A2B3C4D5E6F7081920A6B /* UpdateNotifier.swift */,
```

在 WLComics target 的 Sources `files` 中，`UpdateChecker.swift in Sources */,` 下一行加入：

```
				7E1A2B3C4D5E6F7081920A6C /* UpdateNotifier.swift in Sources */,
```

加入後 `grep -c 7E1A2B3C4D5E6F7081920A6 WLComics.xcodeproj/project.pbxproj` 應為 4。

- [ ] **Step 3: 交給使用者 build**

請使用者 build。
預期：build 成功。App 行為不變。

---

### Task 4: App 內的 UI 與前景檢查

**Files:**
- Modify: `WLComics/View Controllers/Custom Comic Cell/ComicTableViewCell.swift`
- Modify: `WLComics/View Controllers/Left View Controllers/FavoriteTableViewController.swift`
- Modify: `WLComics/View Controllers/Left View Controllers/ComicEpisodesViewController.swift:60-69`
- Modify: `WLComics/View Controllers/Left View Controllers/MasterViewController.swift:318-325`
- Modify: `WLComics/SceneDelegate.swift`
- Modify: `WLComics/AppDelegate.swift`（已有收藏時詢問權限）

**Interfaces:**
- Consumes: Task 1–3 的全部介面
- Produces:
  - `ComicTableViewCell.showsUpdateBadge: Bool`
  - `SceneDelegate.showFavoritesTab()`（Task 5 的通知點擊會用到）

- [ ] **Step 1: cell 加上 NEW 標籤**

`ComicTableViewCell.swift`：在 `var favoriteButtonPress` 宣告後加入：

```swift
    /// 收藏列表標示有新集數；預設隱藏，放在愛心按鈕的位置（收藏列表會隱藏愛心）
    private let updateBadgeLabel: UILabel = {
        let label = UILabel()
        label.text = "NEW"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .systemRed
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    var showsUpdateBadge: Bool {
        get { return !updateBadgeLabel.isHidden }
        set { updateBadgeLabel.isHidden = !newValue }
    }
```

把 `awakeFromNib` 改成：

```swift
    override func awakeFromNib() {
        super.awakeFromNib()
        // 空心愛心（dislike）是 template 圖，用系統次要文字色，深色模式下才看得到
        favoriteBtn.tintColor = .secondaryLabel

        contentView.addSubview(updateBadgeLabel)
        NSLayoutConstraint.activate([
            updateBadgeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            updateBadgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            updateBadgeLabel.widthAnchor.constraint(equalToConstant: 36),
            updateBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        showsUpdateBadge = false
    }
```

- [ ] **Step 2: 收藏列表顯示 NEW、下拉重新整理、取消收藏時更新 badge**

`FavoriteTableViewController.swift`：

在 `import Kingfisher` 下一行加入：

```swift
import SVProgressHUD
```

在 `viewDidLoad` 最後（`FavoriteComics.didChangeNotification` 的 addObserver 之後）加入：

```swift
        // 有新集數的標記變動（檢查完成、看過、其他裝置同步）時重新整理
        NotificationCenter.default.addObserver(self, selector: #selector(trackingDidChange),
                                               name: UpdateTracker.didChangeNotification, object: nil)
        // 下拉強制檢查更新，不受每天一次的限制
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
```

在 `favoritesDidChange()` 之後加入：

```swift
    @objc func trackingDidChange() {
        tableView.reloadData()
    }

    @objc func pullToRefresh() {
        UpdateChecker.shared.check(reason: .manual) { [weak self] result in
            // 人就在 App 裡看得到 NEW，不需要再推播
            UpdateTracker.markNotified(comicIds: result.updates.map { $0.comicId })
            self?.refreshControl?.endRefreshing()
            if result.failedCount > 0 {
                SVProgressHUD.showInfo(withStatus: "\(result.failedCount) 部檢查失敗")
                SVProgressHUD.dismiss(withDelay: 1.5)
            }
        }
    }
```

在 `cellForRowAt` 中，`cell.comicNametextLabel.text = comicDict.object(forKey: "name") as? String` 的下一行加入：

```swift
        if let comicId = comicDict.object(forKey: "comic_id") as? String {
            cell.showsUpdateBadge = UpdateTracker.hasUpdate(comicId: comicId)
        }
```

在 `commit editingStyle` 中，`FavoriteComics.removeComicFromMyFavorite(deleteComic)` 的下一行加入：

```swift
            UpdateBadge.refresh()
```

- [ ] **Step 3: 進入集數列表時標記已看過**

`ComicEpisodesViewController.swift` 的 `viewDidLoad`，把線上載入的 callback：

```swift
                DispatchQueue.main.async {
                    self.allEpisodes = episodes
                    self.refreshLastRead()
```

改成：

```swift
                DispatchQueue.main.async {
                    self.allEpisodes = episodes
                    // 看過集數列表就清掉 NEW 標記（只追蹤收藏的漫畫；0 集時 markSeen 會忽略）
                    if FavoriteComics.checkComicIsMyFavorite(self.currentComic) {
                        UpdateTracker.markSeen(comicId: self.currentComic.getId(), episodeCount: episodes.count)
                    }
                    self.refreshLastRead()
```

（`offlineMode` 的分支不改。）

- [ ] **Step 4: 漫畫列表加入收藏時詢問權限、取消收藏時更新 badge**

`MasterViewController.swift` 的 `favoriteButtonPress` closure，把：

```swift
            if isFavorite {
                FavoriteComics.removeComicFromMyFavorite(comic)
                self.favoriteIds.remove(comic.getId())
            } else {
                FavoriteComics.addComicToMyFavorite(comic)
                self.favoriteIds.insert(comic.getId())
            }
```

改成：

```swift
            if isFavorite {
                FavoriteComics.removeComicFromMyFavorite(comic)
                self.favoriteIds.remove(comic.getId())
                UpdateBadge.refresh()
            } else {
                FavoriteComics.addComicToMyFavorite(comic)
                self.favoriteIds.insert(comic.getId())
                // 第一次收藏時才詢問通知權限，使用者比較能理解用途
                UpdateNotifier.requestAuthorizationIfNeeded()
            }
```

- [ ] **Step 5: 已有收藏的使用者在啟動時詢問權限**

`AppDelegate.swift` 的 `didFinishLaunchingWithOptions`，在 Task 1 加入的 `UpdateTracker.startCloudSync()` 下一行加入：

```swift
        // 已有收藏的使用者，更新後第一次啟動時詢問通知權限（只會問一次）
        if !FavoriteComics.listAllFavorite().isEmpty {
            UpdateNotifier.requestAuthorizationIfNeeded()
        }
```

- [ ] **Step 6: SceneDelegate 接上前景檢查與 badge**

`SceneDelegate.swift`：在 `tabBarController.viewControllers = (tabBarController.viewControllers ?? []) + [downloads]` 的下一行（仍在 `if let tabBarController` 區塊內）加入：

```swift
                UpdateBadge.favoritesTabItem = tabBarController.viewControllers?
                    .first(where: SceneDelegate.isFavoritesTab)?.tabBarItem
```

在 `scene(_:willConnectTo:options:)` 的最後（最外層 `if let splitViewController` 區塊結束之後）加入：

```swift
        // 追蹤資料或收藏變動時更新分頁與 App 圖示的數字
        NotificationCenter.default.addObserver(forName: UpdateTracker.didChangeNotification,
                                               object: nil, queue: .main) { _ in UpdateBadge.refresh() }
        NotificationCenter.default.addObserver(forName: FavoriteComics.didChangeNotification,
                                               object: nil, queue: .main) { _ in UpdateBadge.refresh() }
        UpdateBadge.refresh()
        checkForUpdates()
```

把 `func sceneWillEnterForeground(_ scene: UIScene) {}` 改成：

```swift
    func sceneWillEnterForeground(_ scene: UIScene) {
        checkForUpdates()
    }
```

在 `sceneDidEnterBackground` 之後、class 結尾 `}` 之前加入：

```swift
    // MARK: - 收藏更新

    /// 前景檢查：每天最多一次（節流在 UpdateChecker 內），結果只標示不推播
    private func checkForUpdates() {
        UpdateChecker.shared.check(reason: .foreground) { result in
            UpdateTracker.markNotified(comicIds: result.updates.map { $0.comicId })
        }
    }

    /// 點擊更新通知時切到「我的收藏」
    func showFavoritesTab() {
        guard let splitViewController = window?.rootViewController as? UISplitViewController,
              let tabBarController = splitViewController.viewControllers.first as? UITabBarController,
              let index = tabBarController.viewControllers?.firstIndex(where: SceneDelegate.isFavoritesTab) else { return }
        tabBarController.selectedIndex = index
    }

    private static func isFavoritesTab(_ viewController: UIViewController) -> Bool {
        return (viewController as? UINavigationController)?.viewControllers.first is FavoriteTableViewController
    }
```

- [ ] **Step 7: 交給使用者 build 並手動驗證**

請使用者 build 並在實機或模擬器執行，依序驗證：

1. **第一次啟動**：收藏都沒有 NEW，「我的收藏」分頁與 App 圖示都沒有 badge。若跳出通知權限詢問，選「允許」。
2. **找 comicId**：在 Xcode 按暫停，lldb 執行 `po UpdateTracker.debugDump()`，每部收藏都應該有 `seen=notified=latest`。
3. **模擬更新**：lldb 執行 `po UpdateTracker.debugRewind(comicId: "<某部的 id>")`，繼續執行，在收藏頁下拉。
   預期：該部出現 NEW，分頁 badge 為 1，回主畫面時 App 圖示 badge 為 1，**沒有**收到通知。
4. **重複觸發**：再做一次步驟 3 的 rewind，然後讓 App 進背景再回前景，並立刻下拉。
   預期：轉圈正常收起，沒有卡住。
5. **斷網**：開啟飛航模式後下拉。
   預期：顯示「N 部檢查失敗」，原有的 NEW 標記不變，不會多出新的 NEW。關閉飛航模式。
6. **標記已看過**：點進有 NEW 的那部，再返回。
   預期：NEW 消失，分頁與 App 圖示 badge 消失。若有第二台裝置，iCloud 同步後那台的 NEW 也會消失。
7. **取消收藏**：rewind 某部使它出現 NEW，然後在收藏頁左滑刪除它。
   預期：badge 數字立刻減少。

---

### Task 5: 背景檢查與推播

**Files:**
- Modify: `WLComics/Info.plist`
- Modify: `WLComics/AppDelegate.swift`

**Interfaces:**
- Consumes: `UpdateChecker.shared.check(reason: .background, completion:)`、`UpdateChecker.shared.cancel()`、`UpdateNotifier.post(_:completion:)`、`UpdateNotifier.identifierPrefix`、`UpdateBadge.refresh()`、`SceneDelegate.showFavoritesTab()`
- Produces: 無

- [ ] **Step 1: Info.plist 加入背景任務 ID 與 Background fetch**

`WLComics/Info.plist` 中，把：

```xml
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER).download.*</string>
	</array>
```

改成：

```xml
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER).download.*</string>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER).checkUpdates</string>
	</array>
```

並在 `<key>UIApplicationSceneManifest</key>` 之前加入（與在 Xcode Capabilities 勾選 Background fetch 效果相同）：

```xml
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
	</array>
```

- [ ] **Step 2: AppDelegate 註冊與排程背景任務**

`AppDelegate.swift`：

把 `import UIKit` 改成：

```swift
import UIKit
import BackgroundTasks
import UserNotifications
```

把 class 宣告改成：

```swift
class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate, UNUserNotificationCenterDelegate {
```

在 `let notificationName = ...` 下一行加入：

```swift

    /// 需和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers（<bundle id>.checkUpdates）一致
    private static let updateTaskId = (Bundle.main.bundleIdentifier ?? "com.webberlai.WLComics") + ".checkUpdates"
    /// 漫畫多半是週刊，一天檢查一次就夠
    private static let updateInterval: TimeInterval = 24 * 60 * 60
```

在 `didFinishLaunchingWithOptions` 中，Task 4 Step 5 加入的權限詢問區塊下一行加入（必須在 `return true` 之前，系統要求背景任務在啟動完成前註冊）：

```swift
        UNUserNotificationCenter.current().delegate = self
        registerUpdateTask()
        scheduleUpdateTask()
```

在 `// MARK: - UISceneSession Lifecycle` 之前加入：

```swift
    // MARK: - 背景檢查收藏更新

    private func registerUpdateTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppDelegate.updateTaskId, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleUpdateTask(task)
        }
    }

    private func scheduleUpdateTask() {
        let request = BGAppRefreshTaskRequest(identifier: AppDelegate.updateTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppDelegate.updateInterval)
        // Mac 或使用者關閉「背景 App 重新整理」時會失敗，此時只靠前景檢查
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 系統叫起背景任務時執行（在背景執行緒），檢查與通知都切回 main thread
    private func handleUpdateTask(_ task: BGAppRefreshTask) {
        scheduleUpdateTask()
        task.expirationHandler = {
            DispatchQueue.main.async { UpdateChecker.shared.cancel() }
        }
        DispatchQueue.main.async {
            UpdateChecker.shared.check(reason: .background) { result in
                UpdateNotifier.post(result.updates) {
                    UpdateBadge.refresh()
                    task.setTaskCompleted(success: true)
                }
            }
        }
    }

    // MARK: - 通知

    /// App 在前景時背景任務剛好跑完，仍顯示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 點擊更新通知時切到「我的收藏」
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(UpdateNotifier.identifierPrefix) {
            let scene = UIApplication.shared.connectedScenes.first { $0.delegate is SceneDelegate }
            (scene?.delegate as? SceneDelegate)?.showFavoritesTab()
        }
        completionHandler()
    }
```

- [ ] **Step 3: 交給使用者 build**

請使用者 build。
預期：build 成功。在 Xcode 的 Target → Signing & Capabilities 中，應該會看到 Background Modes 的 Background fetch 已被勾選（由 Info.plist 帶入）。

- [ ] **Step 4: 手動驗證背景通知**

請使用者在**實機**上執行（模擬器的背景任務模擬不可靠）：

1. lldb 執行 `po UpdateTracker.debugRewind(comicId: "<某部的 id>")`，繼續執行。這也會清掉上次檢查時間。
2. 按 Home 讓 App 進背景，然後在 Xcode 按暫停，lldb 執行：
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.webberlai.WLComics.checkUpdates"]
   ```
   再按繼續。
   預期：幾秒內收到「<漫畫名> / 有新集數：<最新集名>」通知，App 圖示 badge 為 1。
3. 點擊通知。
   預期：App 開啟並切到「我的收藏」，該部顯示 NEW。
4. **中止處理**：重做步驟 1，進背景後先執行上面的 `_simulateLaunchForTaskWithIdentifier`，按繼續後立刻再暫停，執行：
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.webberlai.WLComics.checkUpdates"]
   ```
   再按繼續。
   預期：Xcode console 沒有「task was not completed」之類的警告，App 不會 crash。
5. **合併通知**：對 4 部以上的收藏各 rewind 一次，再做步驟 2。
   預期：只收到一則「收藏有更新 / N 部收藏有更新」。
