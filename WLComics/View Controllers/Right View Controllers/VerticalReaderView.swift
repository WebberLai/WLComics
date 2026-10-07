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
    /// 已觸發換集，下一集載入前不再觸發，避免連拉兩次跳過一集
    private var didRequestEpisodeChange = false
    /// 下載完成、等待一起重新排版的頁面（頁碼 → 真實高寬比）
    private var pendingRatios = [Int: CGFloat]()
    private var isRelayoutScheduled = false

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
        // 版面還是舊的，縮放還原與重新排版期間不能觸發頁碼計算
        isAdjustingOffset = true
        scrollView.zoomScale = 1
        layoutPages()
        isAdjustingOffset = false
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
        scrollView.setContentOffset(CGPoint(x: offsetX, y: y), animated: animated)
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
            requestNextEpisode()
            return
        }
        let y = min(scrollView.contentOffset.y + scrollView.bounds.height * VerticalReaderView.keyboardScrollRatio, maxOffsetY)
        scrollView.setContentOffset(CGPoint(x: offsetX, y: y), animated: true)
    }

    /// 鍵盤 ← 往上捲；已在最頂時換上一集
    func previousButtonPressed() {
        guard !images.isEmpty else { return }
        if scrollView.contentOffset.y <= 1 {
            requestPreviousEpisode()
            return
        }
        let y = max(scrollView.contentOffset.y - scrollView.bounds.height * VerticalReaderView.keyboardScrollRatio, 0)
        scrollView.setContentOffset(CGPoint(x: offsetX, y: y), animated: true)
    }

    // MARK: - 版面

    private var maxOffsetY: CGFloat {
        return max(0, scrollView.contentSize.height - scrollView.bounds.height)
    }

    /// 沒有放大時水平位置一律歸零，避免縮放還原後殘留偏移
    private var offsetX: CGFloat {
        return scrollView.zoomScale > 1.001 ? scrollView.contentOffset.x : 0
    }

    private func requestNextEpisode() {
        guard !didRequestEpisodeChange else { return }
        didRequestEpisodeChange = true
        onSwipePastLastPage?()
    }

    private func requestPreviousEpisode() {
        guard !didRequestEpisodeChange else { return }
        didRequestEpisodeChange = true
        onSwipePastFirstPage?()
    }

    private func reload() {
        // 起始頁先存下來：下面清版面、還原縮放、改 contentSize 都可能觸發 scrollViewDidScroll，
        // 若用當下（上一集底部）的位置重算頁碼，會把起始頁蓋成新一集的最後一頁
        let startPage = images.isEmpty ? 0 : min(max(currentIndex, 0), images.count - 1)
        generation += 1
        cancelAllDownloads()

        isAdjustingOffset = true
        // 換集通常發生在拉過底部放手後，回彈動畫還在跑，先停掉
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        pageTops = []
        pendingRatios.removeAll()
        didRequestEpisodeChange = false
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = images.map { _ in makeImageView() }
        imageViews.forEach { contentView.addSubview($0) }
        aspectRatios = Array(repeating: VerticalReaderView.estimatedAspectRatio, count: images.count)
        loadedIndices.removeAll()
        lastReportedPage = -1
        scrollView.zoomScale = 1
        currentIndex = startPage
        // 還沒有寬度時等 layoutSubviews 排版（它會用 currentIndex 當起始頁）
        if layoutWidth > 0 {
            layoutPages()
        }
        isAdjustingOffset = false

        if layoutWidth > 0 {
            scrollToPage(startPage, animated: false)
        }
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
        guard order.contains(where: { !loadedIndices.contains($0) }) else { return }

        // 條漫原圖寬度不大，不降採樣（DownsamplingImageProcessor 以長邊為上限，會把長圖縮得太窄）
        let options: KingfisherOptionsInfo = [.transition(ImageTransition.fade(1)),
                                              .requestModifier(WLComics.sharedInstance().buildDownloadEpisodeHeader(referer)),
                                              .retryStrategy(retryStrategy),
                                              .cacheOriginalImage]
        let round = generation
        for index in order where !loadedIndices.contains(index) {
            guard let url = URL(string: images[index]) else { continue }
            loadedIndices.insert(index)
            imageViews[index].kf.setImage(with: url, placeholder: placeholder, options: options) { [weak self] result in
                guard let self = self, round == self.generation else { return }
                switch result {
                case .success(let value):
                    self.imageDidLoad(at: index, size: value.image.size)
                case .failure(let error):
                    // 被取消（釋放或換集）或被同一個 view 的新請求取代時不處理，避免誤刪追蹤紀錄
                    if error.isTaskCancelled || error.isNotCurrentTask { return }
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

    /// 圖片下載完成：記住真實比例，排到下一輪一起重新排版。
    /// Kingfisher 命中記憶體快取時會在 setImage 當下同步回呼，直接排版會在載入迴圈中重入
    private func imageDidLoad(at index: Int, size: CGSize) {
        guard size.width > 0, size.height > 0, index < aspectRatios.count else { return }
        let ratio = size.height / size.width
        guard abs(ratio - aspectRatios[index]) > 0.001 else { return }
        pendingRatios[index] = ratio
        guard !isRelayoutScheduled else { return }
        isRelayoutScheduled = true
        let round = generation
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRelayoutScheduled = false
            guard round == self.generation else { return }
            self.applyPendingRatios()
        }
    }

    /// 套用新比例並重新排版；頂端在目前捲動位置之上的頁面高度改變時，同步移動捲動位置，畫面內容才不會被推動
    private func applyPendingRatios() {
        // 縮放手勢進行中先不動版面，結束後再套用
        guard !pendingRatios.isEmpty, layoutWidth > 0, !pageTops.isEmpty, !scrollView.isZooming else { return }
        let scale = scrollView.zoomScale
        let offset = scrollView.contentOffset
        var delta: CGFloat = 0
        for (index, ratio) in pendingRatios where index < aspectRatios.count {
            if pageTops[index] * scale < offset.y {
                delta += (ratio - aspectRatios[index]) * layoutWidth * scale
            }
            aspectRatios[index] = ratio
        }
        pendingRatios.removeAll()

        isAdjustingOffset = true
        layoutPages()
        if delta != 0 {
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
        guard !isAdjustingOffset else { return }
        applyPendingRatios()
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
            requestNextEpisode()
        } else if topOverscroll > VerticalReaderView.overscrollThreshold {
            requestPreviousEpisode()
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
