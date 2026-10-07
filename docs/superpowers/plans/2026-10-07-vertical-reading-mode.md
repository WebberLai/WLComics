# 上下捲動閱讀模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增上下連續捲動的閱讀模式（可縮放），依第一頁寬高比自動選擇模式，閱讀器上可手動切換，並記住每部漫畫的模式。

**Architecture:** 新增 `VerticalReaderView`（可縮放的 `UIScrollView`，頁面由上往下排列、延遲載入），以程式碼疊在 storyboard 的 `imgSlider` 上方，由 `DetailViewController` 依模式切換顯示。`ReadingModeStore` 依 `ReadingProgress` 的寫法存每部漫畫的模式並同步 iCloud。`CPImageSlider` 只新增「第一頁尺寸」回呼供自動判斷。

**Tech Stack:** Swift 5、UIKit、Kingfisher、`NSUbiquitousKeyValueStore`。

**Spec:** `docs/superpowers/specs/2026-10-07-vertical-reading-mode-design.md`

## Global Constraints

- 最低版本 iOS 14.0。
- 縮放範圍 1–3 倍；雙擊在 1 倍時放大到 2 倍，否則還原。
- 未下載頁面的預估高寬比 1.5；自動判斷門檻：高 / 寬 ≥ 2.0 為上下捲動。
- 延遲載入範圍：可見範圍上下各 1.5 個畫面高度；釋放範圍：超出上下各 3 個畫面高度。
- 換集門檻：放手時超出頂部或底部 80pt。
- 鍵盤／方向鍵：上下捲動模式一次捲 0.9 個畫面高度。
- iCloud KVS key：`reading_mode`；`source` 值為 `auto` 或 `manual`，`manual` 優先。
- 上下捲動模式不降採樣（見規格）。
- Referer 一律用 `WLComics.sharedInstance().buildDownloadEpisodeHeader(episodeUrl)`。
- 所有 UI 文字使用台灣繁體中文。
- 專案沒有 test target：每個任務的驗證是交給使用者在 Xcode build（不要自行執行 `xcodebuild`），最後依「驗證」段落手動測試。
- 使用者自己 commit；不要 commit。
- 新增 `.swift` 檔要手動加進 `WLComics.xcodeproj/project.pbxproj` 的 WLComics target（`WLMacComic` 不要動）。

## Review Focus

1. **上方頁面載入改變高度時畫面跳動**：使用者正在看的內容不應被推動。→ Task 2 的 `imageDidLoad` 補償 `contentOffset`。驗證：步驟 4。
2. **頁數很少、內容比畫面短**：任何拖曳都不應誤觸換集。→ Task 2 的 `scrollViewWillEndDragging` 用 `max(contentSize.height, bounds.height)` 計算底部。驗證：開一集只有 1–2 頁的漫畫拖曳一下。
3. **自動判斷時 slider 正在自己的下載 completion 中**：此時切換模式會在 slider 的回呼中重建它自己。→ Task 4 的 `onFirstPageImageSize` 處理延到下一個 main runloop。驗證：步驟 2。
4. **快速換集時舊下載晚到**：舊集的圖片尺寸不可寫進新集的版面。→ Task 2 的 `generation`；Task 3 的 `images.first == url` 比對。驗證：連續快速換集幾次。
5. **切換模式時頁碼遺失**：手動切換後要停在同一頁，且不能把閱讀進度重設成第 1 頁。→ Task 4 的 `show(mode:...page:)` 傳入 `currentPage`。驗證：步驟 8。

---

## 檔案結構

| 檔案 | 動作 | 職責 |
|---|---|---|
| `WLComics/ReadingModeStore.swift` | 新增 | `ReadingMode` 與每部漫畫的模式設定、iCloud 合併 |
| `WLComics/View Controllers/Right View Controllers/VerticalReaderView.swift` | 新增 | 上下捲動閱讀器 |
| `WLComics/3rd Image Slider/CPImageSlider/CPImageSlider.swift` | 修改 | 新增 `onFirstPageImageSize` |
| `WLComics/View Controllers/Right View Controllers/DetailViewController.swift` | 修改 | 兩種閱讀器的切換、模式按鈕、自動判斷 |
| `WLComics/View Controllers/Left View Controllers/EpisodeDetailViewController.swift` | 修改 | 點縮圖改呼叫 `DetailViewController.scrollToPage` |
| `WLComics/AppDelegate.swift` | 修改 | 啟動同步 |
| `WLComics.xcodeproj/project.pbxproj` | 修改 | 加入兩個新檔 |

---

### Task 1: ReadingModeStore

**Files:**
- Create: `WLComics/ReadingModeStore.swift`
- Modify: `WLComics.xcodeproj/project.pbxproj`
- Modify: `WLComics/AppDelegate.swift`

**Interfaces:**
- Produces:
  - `enum ReadingMode: String { case horizontal, vertical }`
  - `ReadingModeStore.mode(for comicId: String) -> ReadingMode?`
  - `ReadingModeStore.setAuto(_ mode: ReadingMode, for comicId: String)`
  - `ReadingModeStore.setManual(_ mode: ReadingMode, for comicId: String)`
  - `ReadingModeStore.startCloudSync()`

- [ ] **Step 1: 建立 `WLComics/ReadingModeStore.swift`**

```swift
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

/// 每部漫畫的閱讀模式。本機存在 UserDefaults，同時寫入 iCloud KVS 跨裝置同步；
/// 手動選擇優先於自動判斷。只在 main thread 呼叫。
class ReadingModeStore: NSObject {

    private static let storeKey = "reading_mode"
    /// KVS 單一 key 上限 1MB，每部漫畫一筆，只保留最近的一千部
    private static let maxEntries = 1000

    private static let sourceAuto = "auto"
    private static let sourceManual = "manual"

    private static let cloudStore = NSUbiquitousKeyValueStore.default

    private typealias Store = [String: [String: Any]]

    // MARK: - 讀寫

    /// 沒有設定時回傳 nil，由閱讀器自動判斷
    static func mode(for comicId: String) -> ReadingMode? {
        guard let raw = loadLocal()[comicId]?["mode"] as? String else { return nil }
        return ReadingMode(rawValue: raw)
    }

    /// 自動判斷的結果；使用者手動選過就不覆蓋
    static func setAuto(_ mode: ReadingMode, for comicId: String) {
        if loadLocal()[comicId]?["source"] as? String == sourceManual { return }
        save(mode, source: sourceAuto, for: comicId)
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
```

- [ ] **Step 2: 把 `ReadingModeStore.swift` 加進 project.pbxproj**

先確認 `grep -c 7E1A2B3C4D5E6F7081920A7 WLComics.xcodeproj/project.pbxproj` 為 0。

在 PBXBuildFile section 中，`7E1A2B3C4D5E6F7081920A6C /* UpdateNotifier.swift in Sources */` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A7C /* ReadingModeStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1A2B3C4D5E6F7081920A7B /* ReadingModeStore.swift */; };
```

在 PBXFileReference section 中，`7E1A2B3C4D5E6F7081920A6B /* UpdateNotifier.swift */ = {isa = PBXFileReference` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A7B /* ReadingModeStore.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = ReadingModeStore.swift; sourceTree = "<group>"; };
```

在 `Favorite Model` group 的 `children` 中，`7E1A2B3C4D5E6F7081920A6B /* UpdateNotifier.swift */,` 下一行加入：

```
				7E1A2B3C4D5E6F7081920A7B /* ReadingModeStore.swift */,
```

在 WLComics target 的 Sources `files` 中，`7E1A2B3C4D5E6F7081920A6C /* UpdateNotifier.swift in Sources */,` 下一行加入：

```
				7E1A2B3C4D5E6F7081920A7C /* ReadingModeStore.swift in Sources */,
```

加入後 `grep -c 7E1A2B3C4D5E6F7081920A7 WLComics.xcodeproj/project.pbxproj` 應為 4，`plutil -lint WLComics.xcodeproj/project.pbxproj` 應為 OK。

- [ ] **Step 3: AppDelegate 啟動同步**

`WLComics/AppDelegate.swift` 中，把：

```swift
        UpdateTracker.startCloudSync()
```

改成：

```swift
        UpdateTracker.startCloudSync()
        ReadingModeStore.startCloudSync()
```

---

### Task 2: VerticalReaderView

**Files:**
- Create: `WLComics/View Controllers/Right View Controllers/VerticalReaderView.swift`
- Modify: `WLComics.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `WLComics.sharedInstance().buildDownloadEpisodeHeader(_:)`
- Produces（class `VerticalReaderView: UIView`）:
  - `var episodeUrl: String?`、`var currentIndex: Int`、`var images: [String]`
  - `var onPageChanged: ((Int) -> Void)?`、`var onSwipePastLastPage: (() -> Void)?`、`var onSwipePastFirstPage: (() -> Void)?`、`var onTap: (() -> Void)?`
  - `func cancelAllDownloads()`、`func scrollToPage(_ page: Int, animated: Bool = true)`、`func nextButtonPressed()`、`func previousButtonPressed()`

- [ ] **Step 1: 建立 `VerticalReaderView.swift`**

```swift
//
//  VerticalReaderView.swift
//  WLComics
//

import UIKit
import Kingfisher

/// 上下連續捲動的閱讀器（條漫用），可縮放。對外介面與 CPImageSlider 一致，只在 main thread 使用。
/// 設定順序和 slider 一樣：先 episodeUrl、currentIndex，最後 images
class VerticalReaderView: UIView, UIScrollViewDelegate {

    /// 一集的網址，當作圖片請求的 Referer
    var episodeUrl: String?

    /// 目前頁碼：畫面上方三分之一的位置落在哪一頁
    var currentIndex = 0

    var images = [String]() {
        didSet { reload() }
    }

    var onPageChanged: ((Int) -> Void)?
    var onSwipePastLastPage: (() -> Void)?
    var onSwipePastFirstPage: (() -> Void)?
    var onTap: (() -> Void)?

    /// 未下載過的頁面先用這個高寬比占位
    private static let estimatedAspectRatio: CGFloat = 1.5
    /// 放手時超出頂部／底部這麼多就換集
    private static let overscrollThreshold: CGFloat = 80
    /// 可見範圍上下各延伸幾個畫面高度內的頁面要載入
    private static let loadMargin: CGFloat = 1.5
    /// 超出可見範圍上下各幾個畫面高度就釋放圖片
    private static let keepMargin: CGFloat = 3
    /// 鍵盤翻頁一次捲動的畫面比例
    private static let keyboardScrollRatio: CGFloat = 0.9

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var imageViews = [UIImageView]()
    /// 每頁的高寬比（高 / 寬）；下載過就記住真實值，釋放圖片後仍保留，版面才不會再變
    private var aspectRatios = [CGFloat]()
    /// 每頁頂端在未縮放內容座標中的 y
    private var pageTops = [CGFloat]()
    private var loadedIndices = Set<Int>()
    /// 每次設定 images 遞增，上一集遲到的下載結果直接丟掉
    private var generation = 0
    private var lastReportedPage = -1
    /// 目前版面所用的寬度；寬度改變時要重新排版
    private var layoutWidth: CGFloat = 0
    /// 程式調整捲動位置時，不重新計算頁碼
    private var isAdjustingOffset = false

    private let retryStrategy = DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2))
    private let placeholder = UIImage(named: "comic_place_holder")

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 3
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(doubleTap)
        scrollView.addGestureRecognizer(singleTap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, width != layoutWidth else { return }
        // 旋轉、分割畫面、調整視窗：以已知比例重新排版，目前頁維持在畫面頂端
        let page = currentIndex
        layoutWidth = width
        scrollView.zoomScale = 1
        layoutPages()
        scrollToPage(page, animated: false)
    }

    // MARK: - 對外操作

    func cancelAllDownloads() {
        imageViews.forEach { $0.kf.cancelDownloadTask() }
    }

    /// 讓該頁頂端對齊畫面頂端（最後幾頁捲不到頂端時停在最底）
    func scrollToPage(_ page: Int, animated: Bool = true) {
        guard !images.isEmpty, layoutWidth > 0 else { return }
        let target = min(max(page, 0), images.count - 1)
        currentIndex = target
        let y = min(pageTops[target] * scrollView.zoomScale, maxOffsetY)
        isAdjustingOffset = true
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: animated)
        isAdjustingOffset = false
        if !animated {
            loadVisibleImages()
            reportPageIfChanged()
        }
    }

    /// 鍵盤 → 往下捲；已在最底時換下一集
    func nextButtonPressed() {
        guard !images.isEmpty else { return }
        if scrollView.contentOffset.y >= maxOffsetY - 1 {
            onSwipePastLastPage?()
            return
        }
        let y = min(scrollView.contentOffset.y + scrollView.bounds.height * VerticalReaderView.keyboardScrollRatio, maxOffsetY)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: true)
    }

    /// 鍵盤 ← 往上捲；已在最頂時換上一集
    func previousButtonPressed() {
        guard !images.isEmpty else { return }
        if scrollView.contentOffset.y <= 1 {
            onSwipePastFirstPage?()
            return
        }
        let y = max(scrollView.contentOffset.y - scrollView.bounds.height * VerticalReaderView.keyboardScrollRatio, 0)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: true)
    }

    // MARK: - 版面

    private var maxOffsetY: CGFloat {
        return max(0, scrollView.contentSize.height - scrollView.bounds.height)
    }

    private func reload() {
        generation += 1
        cancelAllDownloads()
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = images.map { _ in makeImageView() }
        imageViews.forEach { contentView.addSubview($0) }
        aspectRatios = Array(repeating: VerticalReaderView.estimatedAspectRatio, count: images.count)
        loadedIndices.removeAll()
        lastReportedPage = -1
        scrollView.zoomScale = 1
        currentIndex = images.isEmpty ? 0 : min(max(currentIndex, 0), images.count - 1)
        // 還沒有寬度時等 layoutSubviews 排版
        guard layoutWidth > 0 else { return }
        layoutPages()
        scrollToPage(currentIndex, animated: false)
    }

    private func makeImageView() -> UIImageView {
        let imageView = UIImageView(image: placeholder)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }

    /// 依每頁高寬比由上往下排列（未縮放座標），並更新 scroll view 的內容大小
    private func layoutPages() {
        var y: CGFloat = 0
        pageTops = []
        for (index, imageView) in imageViews.enumerated() {
            let height = layoutWidth * aspectRatios[index]
            imageView.frame = CGRect(x: 0, y: y, width: layoutWidth, height: height)
            pageTops.append(y)
            y += height
        }
        // contentView 縮放時帶有 transform，只能改 bounds 與 center，不能直接設 frame
        contentView.bounds = CGRect(x: 0, y: 0, width: layoutWidth, height: y)
        let scale = scrollView.zoomScale
        let size = CGSize(width: layoutWidth * scale, height: y * scale)
        contentView.center = CGPoint(x: size.width / 2, y: size.height / 2)
        scrollView.contentSize = size
    }

    /// 未縮放內容座標 y 落在哪一頁
    private func pageIndex(atContentY y: CGFloat) -> Int {
        var result = 0
        for (index, top) in pageTops.enumerated() {
            if top <= y { result = index } else { break }
        }
        return result
    }

    /// 可見範圍上下各延伸 margin 個畫面高度內的頁碼範圍
    private func pageRange(margin: CGFloat) -> ClosedRange<Int>? {
        guard !images.isEmpty, !pageTops.isEmpty else { return nil }
        let scale = scrollView.zoomScale
        let viewTop = scrollView.contentOffset.y / scale
        let viewHeight = scrollView.bounds.height / scale
        let first = pageIndex(atContentY: viewTop - viewHeight * margin)
        let last = pageIndex(atContentY: viewTop + viewHeight * (1 + margin))
        return first...last
    }

    // MARK: - 載入

    private func loadVisibleImages() {
        guard let referer = episodeUrl, let range = pageRange(margin: VerticalReaderView.loadMargin) else { return }
        releaseFarImages()

        // 目前頁優先，接著往下讀的方向，最後才是上面的頁
        let current = min(max(currentIndex, range.lowerBound), range.upperBound)
        var order = Array(current...range.upperBound)
        if current > range.lowerBound {
            order.append(contentsOf: (range.lowerBound..<current).reversed())
        }
        let pending = order.filter { !loadedIndices.contains($0) }
        guard !pending.isEmpty else { return }

        // 條漫原圖寬度不大，不降採樣（DownsamplingImageProcessor 以長邊為上限，會把長圖縮得太窄）
        let options: KingfisherOptionsInfo = [.transition(ImageTransition.fade(1)),
                                              .requestModifier(WLComics.sharedInstance().buildDownloadEpisodeHeader(referer)),
                                              .retryStrategy(retryStrategy),
                                              .cacheOriginalImage]
        let round = generation
        for index in pending {
            guard let url = URL(string: images[index]) else { continue }
            loadedIndices.insert(index)
            imageViews[index].kf.setImage(with: url, placeholder: placeholder, options: options) { [weak self] result in
                guard let self = self, round == self.generation else { return }
                switch result {
                case .success(let value):
                    self.imageDidLoad(at: index, size: value.image.size)
                case .failure:
                    // 下次捲回來重新嘗試
                    self.loadedIndices.remove(index)
                }
            }
        }
    }

    /// 釋放離可見範圍太遠的圖片並取消下載；高寬比保留，版面不變
    private func releaseFarImages() {
        guard let keep = pageRange(margin: VerticalReaderView.keepMargin) else { return }
        for index in loadedIndices.filter({ !keep.contains($0) }) {
            loadedIndices.remove(index)
            imageViews[index].kf.cancelDownloadTask()
            imageViews[index].image = placeholder
        }
    }

    /// 圖片下載完成：記住真實比例，比例不同時重新排版，並補償捲動位置避免畫面跳動
    private func imageDidLoad(at index: Int, size: CGSize) {
        guard size.width > 0, size.height > 0, index < aspectRatios.count else { return }
        let ratio = size.height / size.width
        let oldRatio = aspectRatios[index]
        guard abs(ratio - oldRatio) > 0.001 else { return }

        let scale = scrollView.zoomScale
        // 頂端在目前捲動位置之上的頁面變高（或變矮），下面的內容會被推動，要同步移動捲動位置
        let isAboveViewport = pageTops[index] * scale < scrollView.contentOffset.y
        let delta = (ratio - oldRatio) * layoutWidth * scale
        aspectRatios[index] = ratio

        isAdjustingOffset = true
        let offset = scrollView.contentOffset
        layoutPages()
        if isAboveViewport {
            scrollView.contentOffset = CGPoint(x: offset.x, y: min(max(offset.y + delta, 0), maxOffsetY))
        }
        isAdjustingOffset = false
        loadVisibleImages()
    }

    private func reportPageIfChanged() {
        guard !images.isEmpty, currentIndex != lastReportedPage else { return }
        lastReportedPage = currentIndex
        onPageChanged?(currentIndex)
    }

    // MARK: - 手勢

    @objc private func handleSingleTap() {
        onTap?()
    }

    /// 1 倍時以點擊位置為中心放大到 2 倍，否則還原
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(1, animated: true)
            return
        }
        let point = gesture.location(in: contentView)
        let scale: CGFloat = 2
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        scrollView.zoom(to: rect, animated: true)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return contentView
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !images.isEmpty, !isAdjustingOffset else { return }
        let y = (scrollView.contentOffset.y + scrollView.bounds.height / 3) / scrollView.zoomScale
        currentIndex = pageIndex(atContentY: y)
        loadVisibleImages()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        loadVisibleImages()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !images.isEmpty else { return }
        // 內容比畫面短時，以畫面高度計算底部，避免隨便一拉就換集
        let contentHeight = max(scrollView.contentSize.height, scrollView.bounds.height)
        let bottomOverscroll = scrollView.contentOffset.y + scrollView.bounds.height - contentHeight
        let topOverscroll = -scrollView.contentOffset.y
        // 只有一頁時可能兩邊同時成立，只觸發下一集
        if bottomOverscroll > VerticalReaderView.overscrollThreshold {
            onSwipePastLastPage?()
        } else if topOverscroll > VerticalReaderView.overscrollThreshold {
            onSwipePastFirstPage?()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { reportPageIfChanged() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        reportPageIfChanged()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        reportPageIfChanged()
    }
}
```

- [ ] **Step 2: 把 `VerticalReaderView.swift` 加進 project.pbxproj**

先確認 `grep -c 7E1A2B3C4D5E6F7081920A8 WLComics.xcodeproj/project.pbxproj` 為 0。

在 PBXBuildFile section 中，`6056EE221F28233F007BBE67 /* DetailViewController.swift in Sources */ = {isa = PBXBuildFile` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A8C /* VerticalReaderView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 7E1A2B3C4D5E6F7081920A8B /* VerticalReaderView.swift */; };
```

在 PBXFileReference section 中，`6056EE211F28233F007BBE67 /* DetailViewController.swift */ = {isa = PBXFileReference` 那行下一行加入：

```
		7E1A2B3C4D5E6F7081920A8B /* VerticalReaderView.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = VerticalReaderView.swift; sourceTree = "<group>"; };
```

在含有 `6056EE211F28233F007BBE67 /* DetailViewController.swift */,` 的 group `children` 中（Right View Controllers），該行下一行加入：

```
				7E1A2B3C4D5E6F7081920A8B /* VerticalReaderView.swift */,
```

在 WLComics target 的 Sources `files` 中，`6056EE221F28233F007BBE67 /* DetailViewController.swift in Sources */,` 下一行加入：

```
				7E1A2B3C4D5E6F7081920A8C /* VerticalReaderView.swift in Sources */,
```

加入後 `grep -c 7E1A2B3C4D5E6F7081920A8 WLComics.xcodeproj/project.pbxproj` 應為 4，`plutil -lint` 應為 OK。

---

### Task 3: CPImageSlider 回報第一頁尺寸

**Files:**
- Modify: `WLComics/3rd Image Slider/CPImageSlider/CPImageSlider.swift`

**Interfaces:**
- Produces: `CPImageSlider.onFirstPageImageSize: ((CGSize) -> Void)?`（每次設定 `images` 後，第一頁第一次下載成功時呼叫一次；在 Kingfisher 的 completion 中同步呼叫）

- [ ] **Step 1: 新增回呼與旗標**

把：

```swift
    var images = [String](){
        didSet{
            lastReportedPage = -1
            loadedIndices.removeAll()
```

改成：

```swift
    /// 第一頁下載成功時回報圖片尺寸（自動判斷閱讀模式用），每次設定 images 後只回報一次
    var onFirstPageImageSize: ((CGSize) -> Void)?
    private var didReportFirstPageSize = false

    var images = [String](){
        didSet{
            lastReportedPage = -1
            didReportFirstPageSize = false
            loadedIndices.removeAll()
```

- [ ] **Step 2: 在下載完成時回報**

把 `loadVisibleImages()` 中的：

```swift
                imageViewArray[viewIndex].kf.setImage(with: url, placeholder: placeholder, options: options) { [weak self] result in
                    if case .failure = result { self?.loadedIndices.remove(imageIndex) }
                }
```

改成：

```swift
                imageViewArray[viewIndex].kf.setImage(with: url, placeholder: placeholder, options: options) { [weak self] result in
                    switch result {
                    case .success(let value):
                        if imageIndex == 0 { self?.reportFirstPageSize(value.image.size, url: url) }
                    case .failure:
                        self?.loadedIndices.remove(imageIndex)
                    }
                }
```

並在 `releaseFarImages()` 之前加入：

```swift
    /// 只回報目前這一集的第一頁（比對網址，丟掉上一集遲到的結果）
    private func reportFirstPageSize(_ size: CGSize, url: URL)
    {
        guard !didReportFirstPageSize, images.first == url.absoluteString else { return }
        didReportFirstPageSize = true
        onFirstPageImageSize?(size)
    }
```

---

### Task 4: DetailViewController 整合與 iPad 縮圖

**Files:**
- Modify: `WLComics/View Controllers/Right View Controllers/DetailViewController.swift`
- Modify: `WLComics/View Controllers/Left View Controllers/EpisodeDetailViewController.swift:148`

**Interfaces:**
- Consumes: Task 1 的 `ReadingMode`、`ReadingModeStore`；Task 2 的 `VerticalReaderView`；Task 3 的 `onFirstPageImageSize`
- Produces: `DetailViewController.scrollToPage(_ page: Int)`

- [ ] **Step 1: 新增屬性**

在 `private var displayedEpisodeName = ""` 下一行加入：

```swift
    /// 目前這一集的頁面網址，切換閱讀模式時交給另一個閱讀器
    private var displayedImages = [String]()

    /// 上下捲動閱讀器（條漫用），疊在 imgSlider 上方，依模式切換顯示
    private let verticalReader = VerticalReaderView()
    private var currentMode: ReadingMode = .horizontal
    /// 打開時還沒有模式設定的漫畫，等第一頁載入後自動判斷
    private var pendingAutoDetectComicId: String?
    /// 條漫判斷門檻：第一頁高 / 寬 >= 2
    private static let verticalAspectThreshold: CGFloat = 2.0
    private lazy var modeButton = UIBarButtonItem(image: nil, style: .plain, target: self, action: #selector(toggleReadingMode))

    /// 目前顯示中的閱讀器所在的頁碼
    private var currentPage: Int {
        return currentMode == .horizontal ? imgSlider.currentIndex : verticalReader.currentIndex
    }
```

- [ ] **Step 2: 改寫 `viewDidLoad` 中的 slider 回呼**

把：

```swift
        // 滑動超過邊界時自動切換上下話
        imgSlider.onSwipePastLastPage = { [weak self] in
            self?.loadNextEpisode()
        }
        imgSlider.onSwipePastFirstPage = { [weak self] in
            self?.loadPreviousEpisode()
        }
        // 每翻到新的一頁就記錄閱讀進度
        imgSlider.onPageChanged = { [weak self] page in
            guard let self = self,
                  let comicId = self.displayedComicId,
                  let url = self.displayedEpisodeUrl else { return }
            ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: self.displayedEpisodeName, page: page)
        }
    }
```

改成：

```swift
        // 滑動超過邊界時自動切換上下話
        imgSlider.onSwipePastLastPage = { [weak self] in
            self?.loadNextEpisode()
        }
        imgSlider.onSwipePastFirstPage = { [weak self] in
            self?.loadPreviousEpisode()
        }
        // 每翻到新的一頁就記錄閱讀進度
        imgSlider.onPageChanged = { [weak self] page in
            self?.saveProgress(page: page)
        }
        // 第一頁載入後自動判斷是不是條漫；延到下一輪再處理，
        // 因為切換模式會清空 slider，不能在它自己的下載 completion 裡進行
        imgSlider.onFirstPageImageSize = { [weak self] size in
            DispatchQueue.main.async { self?.autoDetectMode(imageSize: size) }
        }
        setUpVerticalReader()
    }

    private func setUpVerticalReader() {
        verticalReader.isHidden = true
        verticalReader.backgroundColor = .systemBackground
        verticalReader.translatesAutoresizingMaskIntoConstraints = false
        let container: UIView = imgSlider.superview ?? view
        container.insertSubview(verticalReader, aboveSubview: imgSlider)
        NSLayoutConstraint.activate([
            verticalReader.topAnchor.constraint(equalTo: imgSlider.topAnchor),
            verticalReader.bottomAnchor.constraint(equalTo: imgSlider.bottomAnchor),
            verticalReader.leadingAnchor.constraint(equalTo: imgSlider.leadingAnchor),
            verticalReader.trailingAnchor.constraint(equalTo: imgSlider.trailingAnchor),
        ])
        verticalReader.onSwipePastLastPage = { [weak self] in
            self?.loadNextEpisode()
        }
        verticalReader.onSwipePastFirstPage = { [weak self] in
            self?.loadPreviousEpisode()
        }
        verticalReader.onPageChanged = { [weak self] page in
            self?.saveProgress(page: page)
        }
        verticalReader.onTap = { [weak self] in
            guard let self = self else { return }
            self.readerTapped(index: self.verticalReader.currentIndex)
        }
        updateModeButton()
    }

    private func saveProgress(page: Int) {
        guard let comicId = displayedComicId, let url = displayedEpisodeUrl else { return }
        ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: displayedEpisodeName, page: page)
    }
```

- [ ] **Step 3: 方向鍵轉給目前的閱讀器**

在 `catchNotification` 中，把：

```swift
        if imgSlider.images.count == 0 {
            print("尚未載入漫畫")
            return
        }

        // 翻到最後／第一頁時，slider 會透過 onSwipePastLastPage / onSwipePastFirstPage 換話，
        // 雙頁模式下也會自動一次翻兩頁
        if action == UIKeyCommand.inputRightArrow {
            imgSlider.nextButtonPressed()
        } else if action == UIKeyCommand.inputLeftArrow {
            imgSlider.previousButtonPressed()
        }
```

改成：

```swift
        if displayedImages.isEmpty {
            print("尚未載入漫畫")
            return
        }

        // 翻到最後／第一頁時，閱讀器會透過 onSwipePastLastPage / onSwipePastFirstPage 換話，
        // 雙頁模式下也會自動一次翻兩頁；上下捲動模式則是捲動約一個畫面
        let isNext = action == UIKeyCommand.inputRightArrow
        guard isNext || action == UIKeyCommand.inputLeftArrow else { return }
        switch currentMode {
        case .horizontal:
            isNext ? imgSlider.nextButtonPressed() : imgSlider.previousButtonPressed()
        case .vertical:
            isNext ? verticalReader.nextButtonPressed() : verticalReader.previousButtonPressed()
        }
```

- [ ] **Step 4: 改寫 `updateEpisode` 並加入模式切換**

把：

```swift
    func updateEpisode(url: String, images: [String], name: String = "", comicId: String? = nil, startPage: Int = 0) {
        DispatchQueue.main.async {
            self.imgSlider.cancelAllDownloads()
            // 要在設定 images 之前更新，images 一設定就會回報頁碼
            self.displayedComicId = comicId
            self.displayedEpisodeUrl = url
            self.displayedEpisodeName = name
            self.imgSlider.currentIndex = min(max(startPage, 0), max(images.count - 1, 0))
            self.imgSlider.episodeUrl = url
            self.imgSlider.images = images
        }
    }
```

改成：

```swift
    func updateEpisode(url: String, images: [String], name: String = "", comicId: String? = nil, startPage: Int = 0) {
        DispatchQueue.main.async {
            // 要在設定 images 之前更新，images 一設定就會回報頁碼
            self.displayedComicId = comicId
            self.displayedEpisodeUrl = url
            self.displayedEpisodeName = name
            self.displayedImages = images
            // 沒有設定過的漫畫先用左右翻頁，第一頁載入後再自動判斷
            let savedMode = comicId.flatMap { ReadingModeStore.mode(for: $0) }
            self.pendingAutoDetectComicId = savedMode == nil ? comicId : nil
            self.show(mode: savedMode ?? .horizontal, page: startPage)
        }
    }

    /// 顯示指定模式的閱讀器，並把目前這一集交給它、停在 page；另一個閱讀器清空並取消下載
    private func show(mode: ReadingMode, page: Int) {
        currentMode = mode
        imgSlider.cancelAllDownloads()
        verticalReader.cancelAllDownloads()
        let images = displayedImages
        let target = min(max(page, 0), max(images.count - 1, 0))
        switch mode {
        case .horizontal:
            verticalReader.images = []
            verticalReader.isHidden = true
            imgSlider.isHidden = false
            imgSlider.currentIndex = target
            imgSlider.episodeUrl = displayedEpisodeUrl
            imgSlider.images = images
        case .vertical:
            imgSlider.images = []
            imgSlider.isHidden = true
            verticalReader.isHidden = false
            verticalReader.currentIndex = target
            verticalReader.episodeUrl = displayedEpisodeUrl
            verticalReader.images = images
        }
        updateModeButton()
    }

    /// 第一頁載入後判斷是不是條漫，結果記成「自動判斷」
    private func autoDetectMode(imageSize size: CGSize) {
        guard let comicId = pendingAutoDetectComicId, comicId == displayedComicId, size.width > 0 else { return }
        pendingAutoDetectComicId = nil
        let mode: ReadingMode = size.height / size.width >= DetailViewController.verticalAspectThreshold ? .vertical : .horizontal
        ReadingModeStore.setAuto(mode, for: comicId)
        if mode == .vertical && currentMode == .horizontal {
            show(mode: .vertical, page: imgSlider.currentIndex)
        }
    }

    /// 導覽列按鈕：手動切換閱讀模式並記住，停在同一頁
    @objc private func toggleReadingMode() {
        guard let comicId = displayedComicId else { return }
        let newMode: ReadingMode = currentMode == .horizontal ? .vertical : .horizontal
        ReadingModeStore.setManual(newMode, for: comicId)
        pendingAutoDetectComicId = nil
        show(mode: newMode, page: currentPage)
    }

    private func updateModeButton() {
        // 圖示表示「按下後會切換成的方向」
        modeButton.image = UIImage(systemName: currentMode == .horizontal ? "arrow.up.and.down" : "arrow.left.and.right")
        navigationItem.rightBarButtonItem = displayedComicId == nil ? nil : modeButton
    }

    /// iPad 左側縮圖：捲到指定頁
    func scrollToPage(_ page: Int) {
        switch currentMode {
        case .horizontal:
            imgSlider.scrollToPage(page)
        case .vertical:
            verticalReader.scrollToPage(page)
        }
    }
```

- [ ] **Step 5: 點擊畫面的處理共用**

把：

```swift
    func sliderImageTapped(slider: CPImageSlider, index: Int) {
        hidden = !hidden
        self.navigationController?.navigationBar.isHidden = hidden
        delegate?.sliderImageTapped(index: index)
    }
```

改成：

```swift
    func sliderImageTapped(slider: CPImageSlider, index: Int) {
        readerTapped(index: index)
    }

    /// 點擊閱讀器：切換導覽列顯示，並同步 iPad 左側縮圖的選取
    private func readerTapped(index: Int) {
        hidden = !hidden
        self.navigationController?.navigationBar.isHidden = hidden
        delegate?.sliderImageTapped(index: index)
    }
```

- [ ] **Step 6: iPad 左側縮圖改呼叫 `scrollToPage`**

`EpisodeDetailViewController.swift` 中，把：

```swift
        // 用 scrollToPage 才會正確換算雙頁模式的位置
        detailViewController?.imgSlider.scrollToPage(indexPath.row)
```

改成：

```swift
        // 交給閱讀器處理：雙頁模式會換算位置，上下捲動模式會捲到該頁頂端
        detailViewController?.scrollToPage(indexPath.row)
```

- [ ] **Step 7: 交給使用者 build 並手動驗證**

請使用者 build 並在 iPhone、iPad（或 Mac）上依序驗證：

1. **日漫**：維持左右翻頁，行為與現在相同。
2. **韓漫第一次打開**：先短暫顯示左右翻頁，第一頁載入後自動切到上下捲動，頁面撐滿寬度。
3. **韓漫第二次打開**：直接以上下捲動顯示，不跳動。
4. **捲動**：一路往下捲，畫面不跳動；快速捲到中段時，未下載的頁面顯示占位圖。
5. **縮放**：雙指放大、雙擊放大與還原正常，放大後可上下左右拖曳。
6. **進度**：捲幾頁後，iPad／Mac 左側集數列表的「上次看到第 N 頁」即時更新；退出後按「繼續閱讀」回到同一頁。
7. **換集**：在底部繼續往上拉進入下一集；在頂部繼續往下拉回到上一集。
8. **手動切換**：在日漫上按右上角按鈕切到上下捲動，停在同一頁；退出再打開仍是上下捲動。韓漫切回左右翻頁也會被記住。
9. **iPad 左側縮圖**：上下捲動模式點縮圖，會捲到該頁。
10. **Mac**：方向鍵在上下捲動模式會捲動、到底再按換集；橫向視窗在上下捲動模式不會變成雙頁；調整視窗大小後目前頁維持在頂端。
11. **離線**：已下載的集數以上下捲動模式閱讀正常。
