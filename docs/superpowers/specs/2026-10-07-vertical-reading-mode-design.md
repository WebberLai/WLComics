# 上下捲動閱讀模式 — 設計規格

日期：2026-10-07

本文件是「兩種閱讀模式」的子項目 ①。子項目 ②（左右翻頁模式的縮放）另寫規格。

> **2026-10-07 修訂：拿掉自動判斷。** 實測依寬高比自動判斷會誤判，改為一律手動切換：沒有手動選過的漫畫一律用左右翻頁。`ReadingModeStore` 只採用 `source = manual` 的資料，早期存下的 `auto` 資料忽略。下文「自動判斷」相關段落已不適用。

## 目標

韓漫（條漫）的頁面又窄又長，在現有的左右翻頁閱讀器中，因為 `.scaleAspectFit` 要把整頁塞進畫面高度，頁面被縮得很小，也無法放大。新增上下連續捲動的閱讀模式來解決這個問題。

- 新增上下捲動模式：頁面撐滿畫面寬度，由上往下連續排列。
- 上下捲動模式支援雙指縮放與雙擊縮放。
- 依第一頁的寬高比自動選擇模式；閱讀器上有按鈕可手動切換；每部漫畫記住各自的模式，並透過 iCloud 同步。
- 捲到一集的底部後繼續往上拉就換下一集，頂部同理換上一集。

### 成功標準

- 打開韓漫時，頁面撐滿寬度，文字清楚可讀。
- 日漫的閱讀體驗與現在完全相同。
- 第二次打開同一部漫畫時，直接以記住的模式顯示，畫面不跳動。
- 上下捲動模式中捲動時，正在看的內容不會因上方圖片載入而被推動。
- 閱讀進度、繼續閱讀、換集、離線閱讀、iPad 左側縮圖、Mac 方向鍵在上下捲動模式中都正常運作。

### 不在範圍內

- 左右翻頁模式的縮放（子項目 ②）。
- 跨集無縫接續（下一集直接接在下方）。
- 全域預設模式設定。
- 上下捲動模式的雙頁顯示。

## 元件

### `VerticalReaderView`（新檔：`WLComics/View Controllers/Right View Controllers/VerticalReaderView.swift`）

純程式碼建立的 `UIView`，對外介面與 `CPImageSlider` 一致，讓 `DetailViewController` 用同一套方式操作：

| 介面 | 說明 |
|---|---|
| `images: [String]` | 設定後重新排版並載入；可能是網路網址或本機 file URL |
| `episodeUrl: String?` | 當作 Referer；必須在 `images` 之前設定 |
| `currentIndex: Int` | 目前頁碼；在設定 `images` 之前設定，會作為起始頁 |
| `onPageChanged: ((Int) -> Void)?` | 停在新的一頁時回報 |
| `onSwipePastLastPage`、`onSwipePastFirstPage: (() -> Void)?` | 換集 |
| `onTap: (() -> Void)?` | 點擊畫面（切換導覽列顯示） |
| `cancelAllDownloads()` | 取消所有下載 |
| `scrollToPage(_ page: Int, animated: Bool)` | 讓該頁頂端對齊畫面頂端 |
| `nextButtonPressed()`、`previousButtonPressed()` | 往下／往上捲約 0.9 個畫面高度；已在底部／頂部時觸發換集 |

**版面**
- 外層為 `UIScrollView`，`minimumZoomScale = 1`、`maximumZoomScale = 3`，縮放對象是內部的內容 view。
- 雙擊：在 1 倍時放大到 2 倍（以點擊位置為中心），否則還原為 1 倍。
- 內容 view 中由上往下排列每頁的 `UIImageView`，寬度為畫面寬度，高度為「寬度 × 該頁高寬比」。
- 每頁的高寬比：已下載過的用真實值（記在陣列中，釋放圖片後保留）；未下載的用預估值 1.5。
- 頁與頁之間沒有間距。

**目前頁碼**
- 畫面上方三分之一位置（以內容座標換算，考慮縮放）落在哪一頁，就是目前頁。
- 捲動停止（`scrollViewDidEndDecelerating`、`scrollViewDidEndDragging` 且不減速、`scrollViewDidEndScrollingAnimation`）時，若頁碼變了就呼叫 `onPageChanged`。

**延遲載入**
- 載入範圍：與「畫面可見範圍向上下各延伸 1.5 個畫面高度」相交的頁面。
- 優先順序：目前頁、往下的頁、往上的頁。
- 離開「可見範圍向上下各延伸 3 個畫面高度」的頁面：取消下載並釋放圖片，高寬比保留。
- 每次捲動時檢查範圍（只在頁碼範圍變化時才實際發出請求）。
- Kingfisher 選項沿用 `CPImageSlider`：`requestModifier(WLComics.sharedInstance().buildDownloadEpisodeHeader(episodeUrl))`、`retryStrategy`、`cacheOriginalImage`、`transition(.fade)`。
- 不降採樣：Kingfisher 的 `DownsamplingImageProcessor` 以寬、高中較大的一邊為上限，條漫長圖會被縮到太窄。條漫原圖寬度通常只有 700–1000 px，直接用原圖；記憶體由「離開可見範圍上下 3 個畫面高度就釋放」控制。
- 本機已下載頁面：`images` 中的 file URL 照現有 slider 的方式交給 Kingfisher 載入。

**高度修正與防跳動**
- 某頁下載完成且真實高寬比與目前使用值不同時，重新計算該頁之後所有頁面的位置。
- 若該頁的頂端在目前捲動位置之上，把 `contentOffset.y` 加上高度差（乘以目前縮放倍率），讓畫面內容保持不動。

**換集**
- 在 `scrollViewWillEndDragging` 判斷：放手時，超出底部（`contentOffset.y + 可見高度 - contentSize.height`）大於 80pt 時呼叫 `onSwipePastLastPage`；超出頂部（`-contentOffset.y`，扣除 inset）大於 80pt 時呼叫 `onSwipePastFirstPage`。
- 兩者同時成立時（例如只有 1 頁）只觸發 `onSwipePastLastPage`。

**版本號**
- 每次設定 `images` 時遞增版本號；下載完成回呼中版本號不符的結果直接丟棄（不更新高寬比、不調整捲動位置）。

**縮放與換集**
- 設定新的 `images` 時，`zoomScale` 還原為 1，再捲到 `currentIndex` 那一頁。

**畫面寬度改變**
- `layoutSubviews` 偵測到寬度改變時：記下目前頁，以新寬度重新排版，再讓目前頁頂端對齊畫面頂端。

### `ReadingModeStore`（新檔：`WLComics/ReadingModeStore.swift`）

每部漫畫的閱讀模式，寫法比照 `ReadingProgress`：

- `enum ReadingMode: String { case horizontal, vertical }`
- 每筆資料（以 `comic_id` 為 key）：`mode`、`source`（`auto` 或 `manual`）、`updated_at`。
- 本機存在 UserDefaults，同時寫入 iCloud KVS 的 `reading_mode`。
- 合併規則（逐部比對）：`manual` 優先於 `auto`；兩筆來源相同時取 `updated_at` 較新的。
- 介面：
  - `static func mode(for comicId: String) -> ReadingMode?`（沒有設定時回傳 nil）
  - `static func setAuto(_ mode: ReadingMode, for comicId: String)`（已有 `manual` 時不覆蓋）
  - `static func setManual(_ mode: ReadingMode, for comicId: String)`
  - `static func startCloudSync()`（在 `AppDelegate` 啟動時呼叫）
- 所有方法只在 main thread 呼叫。

### 自動判斷

- 判斷條件：這一集第一張下載成功的頁面（不限第 1 頁，從中間繼續閱讀時第 1 頁不會載入）`高 / 寬 >= 2.0` 視為條漫，使用上下捲動模式；否則為左右翻頁模式。
- 時機：打開一集時，若 `ReadingModeStore.mode(for:)` 為 nil，先以左右翻頁模式顯示，並監聽第一頁下載成功；拿到尺寸後呼叫 `setAuto`，若結果為上下捲動模式就切換。
- 原圖尺寸來源：Kingfisher 下載完成回呼中的 `RetrieveImageResult.image`（降採樣後的比例與原圖相同，用比例判斷即可）。`CPImageSlider` 需新增 `onFirstPageImageSize` 回呼（只在第一頁、且版本相符時觸發一次）。
- 第一頁下載失敗：不判斷，維持左右翻頁模式，不寫入設定，下次打開再判斷。

### `DetailViewController` 的改動

- 程式建立 `verticalReader: VerticalReaderView`，與 storyboard 的 `imgSlider` 相同 frame 與約束，預設隱藏。
- 新增 `currentMode: ReadingMode` 與 `applyMode(_:)`：
  - 切換顯示哪一個 view；被隱藏的那個 `cancelAllDownloads()` 並清空 `images`。
  - 把目前這一集的 `episodeUrl`、`images`、目前頁碼交給新的 view（停留在同一頁）。
- `updateEpisode(url:images:name:comicId:startPage:)`：
  - 依 `ReadingModeStore.mode(for: comicId)` 決定模式（nil 時用左右翻頁並啟用自動判斷）。
  - 只對目前顯示的 view 設定 `episodeUrl`、`currentIndex`、`images`。
- 兩個 view 的 `onPageChanged`、`onSwipePastLastPage`、`onSwipePastFirstPage` 接到相同的處理（現有的進度紀錄與換集邏輯不變）。
- 鍵盤方向鍵（`catchNotification`）：轉給目前顯示的 view 的 `nextButtonPressed()` / `previousButtonPressed()`。
- 新增 `scrollToPage(_ page: Int)`，轉給目前顯示的 view；`EpisodeDetailViewController` 改呼叫這個方法，不再直接操作 `imgSlider.scrollToPage`。`imgSlider.currentIndex = 0` 的初始化保留（只影響 slider）。
- 導覽列新增切換按鈕：左右翻頁模式時顯示 `arrow.up.and.down`，上下捲動模式時顯示 `arrow.left.and.right`。按下後 `ReadingModeStore.setManual(...)` 並 `applyMode`。沒有 `comicId` 時按鈕隱藏。
- 雙頁模式：`viewDidLayoutSubviews` 中的 `isSpreadMode` 判斷只套用在 `imgSlider`；上下捲動模式不受影響。
- 點擊畫面：`verticalReader.onTap` 執行與 `sliderImageTapped` 相同的導覽列切換。

### `AppDelegate`

- 啟動時呼叫 `ReadingModeStore.startCloudSync()`。

## 錯誤處理

| 情況 | 處理 |
|---|---|
| 某頁下載失敗 | 保留預估高度的占位圖；從已載入集合移除，捲回來時重新嘗試 |
| 第一頁下載失敗 | 不做自動判斷，維持左右翻頁，不寫入設定 |
| 換集時舊下載晚到 | 版本號不符，丟棄 |
| 縮放中換集 | 還原為 1 倍，捲到起始頁 |
| 只有 1 頁時放手超出頂部與底部 | 只觸發下一集 |
| 畫面寬度改變 | 以已知比例重新排版，目前頁維持在頂端 |
| `episodeUrl` 尚未設定 | 不發出下載（與 slider 相同） |

## 驗證方式

專案沒有 test target，由使用者在 Xcode build 並手動驗證：

1. 日漫：維持左右翻頁，行為與現在相同。
2. 韓漫第一次打開：先短暫顯示左右翻頁，第一頁載入後自動切到上下捲動，頁面撐滿寬度。
3. 韓漫第二次打開：直接以上下捲動顯示，不跳動。
4. 一路往下捲，畫面不跳動；快速捲到中段時，未下載的頁面顯示占位圖。
5. 雙指放大、雙擊放大與還原正常，放大後可上下左右拖曳。
6. 捲幾頁後，iPad／Mac 左側集數列表的「上次看到第 N 頁」即時更新；退出後按「繼續閱讀」回到同一頁。
7. 在底部繼續往上拉進入下一集；在頂部繼續往下拉回到上一集。
8. 日漫手動切到上下捲動，退出再打開仍是上下捲動；韓漫切回左右翻頁也會被記住。
9. iPad 左側點縮圖，上下捲動模式會捲到該頁。
10. Mac：方向鍵在上下捲動模式會捲動；橫向視窗在上下捲動模式不會變成雙頁；調整視窗大小後目前頁維持在頂端。
11. 已下載的集數以上下捲動模式離線閱讀正常。
