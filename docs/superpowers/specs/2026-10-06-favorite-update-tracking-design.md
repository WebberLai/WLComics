# 收藏漫畫追更新 — 設計規格

日期：2026-10-06

## 目標

讓使用者知道「我的最愛」裡的漫畫出了新集數，不必逐一點進去確認。

- 只追蹤「我的最愛」裡的漫畫。
- App 內標示：收藏列表的 cell 加上 NEW，「我的最愛」分頁顯示 badge。
- App 圖示 badge：主畫面的 App 圖示顯示有更新的部數。
- 背景每天檢查一次，有更新時發本地通知。
- 「我的最愛」支援下拉重新整理，手動強制檢查。

### 成功標準

- 收藏的漫畫多了一集後，在下一次檢查（前景、背景或下拉）完成時出現 NEW 標記、分頁 badge 與 App 圖示 badge。
- 進入該漫畫的集數列表後，NEW 標記與兩種 badge 都減少，其他裝置透過 iCloud 同步後也一併消失。
- 同一次更新最多推播一次，跨裝置也不重複。
- 網站改版導致解析失敗時，不會誤判成大量更新。

### 不在範圍內

- 追蹤非收藏的漫畫。
- 自動下載新集數。
- 點擊通知後直接開啟該漫畫的集數列表（只切到「我的最愛」分頁）。
- 依閱讀進度計算未讀集數。
- 收藏列表依更新狀態重新排序。

## 判斷規則

每部收藏記錄四個欄位（key 為 `comic_id`）：

| 欄位 | 意義 | 何時更新 |
|---|---|---|
| `seen_count` | 使用者上次看過的集數 | 進入集數列表且線上載入成功 |
| `notified_count` | 上次推播（或前景已顯示）時的集數 | 背景發通知、前景或下拉檢查完成、進入集數列表（看過就不需要再通知） |
| `latest_count` | 最近一次檢查抓到的集數 | 每次檢查成功 |
| `checked_at` | 最近一次檢查成功的時間 | 每次檢查成功 |

- 有 NEW：`latest_count > seen_count`
- 要推播：`latest_count > notified_count`（只在背景檢查時發）
- **第一次追蹤**（沒有資料的漫畫）：三個 count 都設為目前集數，不顯示 NEW，也不推播。
- **集數變少**（且大於 0）：三個 count 都重設為新的集數。
- **解析出 0 集**：視為檢查失敗，資料完全不動。

## 元件

### `UpdateTracker.swift`（新檔）

只負責存取上述資料，寫法比照 `ReadingProgress`：

- 本機存在 UserDefaults，同時寫入 iCloud KVS，key 為 `episode_tracking`。
- 監聽 `NSUbiquitousKeyValueStore.didChangeExternallyNotification`，只處理 `episode_tracking` 的變動。
- 合併規則（逐部比對）：`seen_count` 與 `notified_count` 取較大值；`latest_count` 取 `checked_at` 較新的那筆。
- 資料變動後發出 `UpdateTracker.didChangeNotification`，讓收藏頁與 badge 重新整理。
- 存放全域的 `last_full_check_at`（只存在本機 UserDefaults，不同步），供 24 小時節流判斷。
- 提供 `prune(keeping:)`，移除不在收藏中的漫畫資料。
- 所有方法都只在 main thread 呼叫（比照 `ReadingProgress`），不另外加鎖。
- 只在 DEBUG 編譯的 `debugRewind(comicId:)`：把 `seen_count` 與 `notified_count` 各減 1，並清除 `last_full_check_at`，用來模擬新集數；清除時間是為了讓接著觸發的背景檢查不被 24 小時節流擋掉。

主要介面：

```swift
static func hasUpdate(comicId: String) -> Bool
static func updatedComicCount() -> Int          // 收藏中有 NEW 的部數，給 badge 用
static func recordCheck(comicId: String, episodeCount: Int)
static func markSeen(comicId: String, episodeCount: Int)
static func markNotified(comicIds: [String])
static func startCloudSync()
```

### `UpdateChecker.swift`（新檔）

負責向網站抓取並比對：

- `check(reason:completion:)`，`reason` 為 `.foreground`、`.background` 或 `.manual`。
  - `.foreground` 與 `.background`：若距 `last_full_check_at` 不到 24 小時，直接結束。
  - `.manual`：不受 24 小時限制。
- 已有檢查在執行時，新的呼叫加入同一次的 completion 清單，不重複發請求。
- 讀取 `FavoriteComics.listAllFavorite()`，最多同時 2 個請求，透過 `WLComics.sharedInstance().getR8Comic().loadComicDetail` 抓集數列表。
- 每個請求自加 20 秒 timeout（SDK 失敗時不會回呼）；逾時或失敗就略過那一部。
- 完成後：
  - 至少一部成功才更新 `last_full_check_at`；全部失敗則不更新，下次回到前景會重試。
  - 呼叫 `UpdateTracker.prune(keeping:)`。
  - 回傳結果：需要推播的漫畫（名稱、最新集名）與失敗數量。
- 支援取消（背景任務 expiration 時呼叫），已完成的結果照常保存。

### `UpdateNotifier`（放在 `UpdateChecker.swift` 或獨立小檔）

- 只處理背景檢查的結果。
- 有更新的漫畫在 3 部以內：每部一則通知，例如「海賊王 有新集數：第 1130 話」。
- 超過 3 部：合併成一則，例如「5 部收藏有更新」。
- 發出後呼叫 `UpdateTracker.markNotified`。
- 前景與下拉檢查不發通知，直接呼叫 `markNotified`，避免之後背景補發。
- 通知權限被拒時不發通知，其他功能照常運作。

### 背景任務（`AppDelegate`）

- 任務 ID：`com.webberlai.WLComics.checkUpdates`。Mac 版是同一個 iOS App 跑在 Mac 上，ID 相同；`WLMacComic` 是另一個舊 target，不在範圍內。程式以 `Bundle.main.bundleIdentifier` 組出 ID，Info.plist 使用 `$(PRODUCT_BUNDLE_IDENTIFIER).checkUpdates`（加在既有的 `BGTaskSchedulerPermittedIdentifiers` 陣列中）。
- 在 `didFinishLaunchingWithOptions` 註冊 `BGAppRefreshTask`，並在啟動與每次任務結束時排程，`earliestBeginDate` 為 24 小時後。
- 任務內呼叫 `UpdateChecker.check(reason: .background)`，完成後交給 `UpdateNotifier`，再 `setTaskCompleted(success:)`。
- expiration handler 取消檢查。
- 設定 `UNUserNotificationCenter` delegate：點擊通知時切到「我的最愛」分頁。
- 啟動時呼叫 `UpdateTracker.startCloudSync()`。

### 通知權限

- 要求 `.alert`、`.sound`、`.badge` 三種權限。
- 第一次加入收藏時詢問（`FavoriteComics.addComicToMyFavorite` 之後，由 UI 端觸發）。
- 已有收藏的使用者：更新後第一次啟動時詢問一次（用 UserDefaults 記錄已詢問過）。

### 前景觸發（`SceneDelegate`）

- `sceneWillEnterForeground` 與首次啟動時呼叫 `UpdateChecker.check(reason: .foreground)`。

### UI

**`FavoriteTableViewController`**
- 加入 `UIRefreshControl`，下拉時呼叫 `check(reason: .manual)`。完成後收起轉圈；有失敗時以 SVProgressHUD 短暫顯示「N 部檢查失敗」。
- cell 依 `UpdateTracker.hasUpdate` 顯示 NEW 標記（使用系統元件，例如小圓點或 `UILabel`，不另做圖片素材）。
- 監聽 `UpdateTracker.didChangeNotification` 後重新整理。
- 不改變既有的拼音分區與手動排序。

**分頁 badge 與 App 圖示 badge**
- 兩者的數字相同，都是 `UpdateTracker.updatedComicCount()`。
- 分頁：「我的最愛」的 `tabBarItem.badgeValue`，為 0 時設成 nil。
- App 圖示：設定 `UIApplication.shared.applicationIconBadgeNumber`（iOS 14 起可用；iOS 16 以上改用 `UNUserNotificationCenter.setBadgeCount`），為 0 時清除。需要 `.badge` 通知權限，被拒時不顯示。
- 由一個 `UpdateBadge.refresh()` 統一更新兩者（main queue），在以下時機呼叫：`UpdateTracker.didChangeNotification`、收藏變動通知、背景檢查完成時（App 未開啟也要更新圖示數字）。
- 本地通知的 content 不另帶 badge 數字，避免和 `refresh()` 算出的數字不一致。

**`ComicEpisodesViewController`**
- 線上模式下 `loadComicDetail` 成功、且集數大於 0 時，呼叫 `UpdateTracker.markSeen(comicId:episodeCount:)`。
- `offlineMode` 時不更新。

### 專案設定

- Background Modes → Background fetch：直接在 Info.plist 加入 `UIBackgroundModes` = `[fetch]`，效果與在 Xcode Capabilities 勾選相同。
- Info.plist：加入 `BGTaskSchedulerPermittedIdentifiers`，值為 `$(PRODUCT_BUNDLE_IDENTIFIER).checkUpdates`。
- 不需要 Push Notifications capability（只用本地通知）。

## 資料流

```
觸發（前景 / 背景 / 下拉）
  → UpdateChecker.check(reason:)
    → 24 小時節流（manual 除外）
    → 逐部 loadComicDetail（最多 2 個同時，20 秒 timeout）
      → UpdateTracker.recordCheck(comicId:, episodeCount:)
    → prune、更新 last_full_check_at
  → background：UpdateNotifier 發通知 → markNotified
    foreground / manual：直接 markNotified
  → UpdateTracker.didChangeNotification → 收藏列表 NEW、分頁 badge 與 App 圖示 badge 更新

進入集數列表（線上）
  → UpdateTracker.markSeen → NEW 與兩種 badge 更新 → 同步至 iCloud
```

## 錯誤處理

| 情況 | 處理 |
|---|---|
| 單部逾時、網路錯誤或 HTTP 非 2xx | 略過那一部，資料不動 |
| 全部失敗 | 不更新 `last_full_check_at`，下次回到前景重試 |
| 解析出 0 集 | 視為失敗，資料不動 |
| 集數變少（大於 0） | 三個 count 重設為新值 |
| 漫畫已不在收藏中 | 下次檢查時 prune |
| 通知權限被拒 | 只略過通知 |
| 重複觸發 | 併入進行中的檢查 |
| 背景任務被系統中止 | 取消剩餘請求，已完成的結果保留 |

執行緒：SDK callback 在背景執行緒，`UpdateChecker` 收到後先切回 main queue，再呼叫 `UpdateTracker` 與更新 UI。

## 平台差異

- iOS / iPadOS：前景檢查、背景檢查與通知皆可用；背景執行頻率由系統決定，可能晚於 24 小時。
- Mac：同樣的程式碼。背景任務的執行頻率更不可靠，以前景檢查與下拉為主。

## 驗證方式

專案沒有 test target，由使用者在 Xcode build 並手動驗證：

1. 第一次啟動：收藏都不出現 NEW，分頁與 App 圖示都沒有 badge。
2. 在 lldb 執行 `po UpdateTracker.debugRewind(comicId: "<id>")`，再下拉重新整理：該部出現 NEW，分頁 badge 為 1，回主畫面時 App 圖示 badge 也為 1，且不收到通知。
3. 進入該部的集數列表後返回：NEW 與兩種 badge 消失。
4. 再執行一次 `debugRewind`，按 Home 讓 App 進入背景，在 Xcode 暫停後執行：
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.webberlai.WLComics.checkUpdates"]`
   繼續執行：收到通知，App 圖示 badge 為 1；點擊後切到「我的最愛」分頁。
5. 關閉網路後下拉：顯示「N 部檢查失敗」，原有標記不變。
6. （有兩台裝置時）一台進入集數列表後，另一台同步完成時 NEW 消失。
