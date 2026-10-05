//
//  CPImageSlider.swift
//  ImageSlider
//
//  Created by Amit Singh on 28/06/17.
//  Copyright © 2017 Code Protocols. All rights reserved.
//

import UIKit
import Kingfisher

@objc protocol CPSliderDelegate: NSObjectProtocol {
    func sliderImageTapped(slider: CPImageSlider, index: Int)
}

class CPImageSlider: UIView, UIScrollViewDelegate {
    
    static var leftArrowImage : UIImage?
    static var rightArrowImage : UIImage?
    
    private var view: UIView!
    
    var lastIndex : Int = 0
    
    @IBOutlet weak fileprivate var myScrollView: UIScrollView!
    @IBOutlet weak fileprivate var myPageControl: UIPageControl!
    
    @IBOutlet weak var pageIndicatorBottomConstraint : NSLayoutConstraint!
    
    @IBOutlet weak fileprivate var prevArrowButton : UIButton!
    @IBOutlet weak fileprivate var nextArrowButton : UIButton!
    @IBOutlet weak fileprivate var arrowButtonsView : UIView!
    
    var currentIndex : Int = 0
    
    var allowCircular : Bool = true{
        didSet{
            addImagesOnScrollView()
        }
    }
    
    var durationTime : TimeInterval = 3.0
    
    var images = [String](){
        didSet{
            lastReportedPage = -1
            loadedIndices.removeAll()
            myPageControl.numberOfPages = images.count
            addImagesOnScrollView()
        }
    }

    var episodeUrl : String?;//一集(話)的漫畫網址，例如http://v.comicbus.com/online/comic-3099.html?ch=2

    // lazy loading：預先載入當前頁面前後各幾頁
    private let prefetchRange = 2

    /// 雙頁（跨頁）模式：一個畫面並排兩頁，右邊是前一頁、左邊是後一頁（日漫順序）。
    /// 只支援非循環模式；currentIndex 仍是頁碼，雙頁時固定為該組的第一頁（偶數）
    var isSpreadMode : Bool = false {
        didSet {
            guard oldValue != isSpreadMode else { return }
            addImagesOnScrollView()
        }
    }

    /// 一個畫面（scroll view 的一格）放幾頁
    var pagesPerSpread : Int {
        return (isSpreadMode && !allowCircular) ? 2 : 1
    }

    /// scroll view 一共有幾格（不含循環模式首尾的複製頁）
    private var spreadCount : Int {
        return (images.count + pagesPerSpread - 1) / pagesPerSpread
    }

    /// 第 index 個 imageView 在 scroll view 中的位置
    private func frameForImageView(at index: Int) -> CGRect
    {
        let width = bounds.width
        guard pagesPerSpread == 2 else {
            return CGRect(x: CGFloat(index)*width, y: 0, width: width, height: bounds.height)
        }
        let spreadX = CGFloat(index / 2) * width
        // 最後一頁落單時佔滿整格，置中顯示
        if index % 2 == 0 && index == images.count - 1 {
            return CGRect(x: spreadX, y: 0, width: width, height: bounds.height)
        }
        let half = width / 2
        // 前一頁（偶數）在右半邊，後一頁在左半邊
        let x = index % 2 == 0 ? spreadX + half : spreadX
        return CGRect(x: x, y: 0, width: half, height: bounds.height)
    }
    
    var enableSwipe : Bool = false{
        didSet{
            myScrollView.isUserInteractionEnabled = enableSwipe
        }
    }
    
    var enableArrowIndicator : Bool = false{
        didSet{
            arrowButtonsView.isHidden = !enableArrowIndicator
        }
    }
    
    var enablePageIndicator : Bool = false{
        didSet{
            myPageControl.isHidden = !enablePageIndicator
        }
    }
    
    var imageViewArray : [UIImageView] = []
    
    var autoSrcollEnabled : Bool = false{
        didSet{
            checkForAutoScrolled()
        }
    }
    
    var activeTimer:Timer?
    
    @IBOutlet weak var delegate: CPSliderDelegate?
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        xibSetup()
        resetValues()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        for (index, imageV) in imageViewArray.enumerated()
        {
            imageV.frame = frameForImageView(at: index)
        }
        var count = spreadCount
        if allowCircular
        {
            count += 2
        }
        myScrollView.contentSize = CGSize(width: bounds.width*CGFloat(count), height: bounds.height)
        adjustContentOffsetFor(index: currentIndex, offsetIndex: convertIndex(), animated: false)
    }
    
    func convertIndex()->Int
    {
        if allowCircular
        {
            return currentIndex + 1
        }
        else
        {
            return currentIndex / pagesPerSpread
        }
    }
    
    func resetValues()
    {
        allowCircular = true
        enableSwipe = true
        enablePageIndicator = true
        enableArrowIndicator = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        xibSetup()
        resetValues()
    }
    
    func xibSetup()
    {
        view = loadViewFromNib()
        // use bounds not frame or it'll be offset
        view.frame = bounds
        // Make the view stretch with containing view
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // xib 內是寫死的白底，改成透明，由外層決定背景色
        view.backgroundColor = .clear
        myScrollView.backgroundColor = .clear
        // Adding custom subview on top of our view (over any custom drawing > see note below)
        addSubview(view)
    }
    
    func loadViewFromNib() -> UIView {
        let bundle = Bundle(for: type(of: self))
        let nib = UINib(nibName: "CPImageSlider", bundle: bundle)
        // Assumes UIView is top level and only object in CPImageSlider.xib file
        let view = nib.instantiate(withOwner: self, options: nil)[0] as! UIView
        return view
    }
    
    func adjustContentOffsetFor(index : Int, offsetIndex offset : Int, animated : Bool)
    {
        currentIndex = index
        myScrollView.setContentOffset(CGPoint(x: CGFloat(offset)*bounds.width, y: 0), animated: animated)
        myPageControl.currentPage = index
        checkButtonsIfNeedsDisable()
        checkForAutoScrolled()
        loadVisibleImages()
        reportPageIfChanged()
    }
    
    func cancelAllDownloads()
    {
        for imageV in imageViewArray {
            imageV.kf.cancelDownloadTask()
        }
    }

    func addImagesOnScrollView()
    {
        // 取消所有舊的下載任務
        cancelAllDownloads()

        // 先鎖住目標 index，並停止任何進行中的減速動畫，
        // 避免接下來修改 contentSize 時 scroll view clamp offset
        // 觸發 delegate callback，把 currentIndex 改成舊的最後一頁
        // 雙頁模式下對齊到該組的第一頁
        let targetIndex = currentIndex - currentIndex % pagesPerSpread
        isRebuildingScrollView = true
        myScrollView.setContentOffset(myScrollView.contentOffset, animated: false)

        for sub in myScrollView.subviews
        {
            sub.removeFromSuperview()
        }
        // 所有 imageView 都會被重設成 placeholder，已載入的紀錄也要一起清掉
        loadedIndices.removeAll()
        if images.count == 0
        {
            isRebuildingScrollView = false
            return
        }
        var count = images.count
        if allowCircular && images.count != 0
        {
            count += 2
        }
        let placeholder = UIImage(named: "comic_place_holder")
        for index in 0..<count
        {
            let imageV = getImageView(index: index)
            imageV.frame = frameForImageView(at: index)
            // 先設定 placeholder，實際圖片由 loadVisibleImages 按需載入
            imageV.image = placeholder
            myScrollView.addSubview(imageV)
        }

        if count < imageViewArray.count {
            imageViewArray.removeSubrange(count..<imageViewArray.count)
        }
        let slotCount = allowCircular ? count : spreadCount
        myScrollView.contentSize = CGSize(width: bounds.width*CGFloat(slotCount), height: bounds.height)
        currentIndex = targetIndex
        adjustContentOffsetFor(index: targetIndex, offsetIndex: convertIndex(), animated: false)
        isRebuildingScrollView = false

        // 載入當前頁面附近的圖片
        loadVisibleImages()
    }

    /// 根據 currentIndex 載入前後 prefetchRange 頁的圖片（lazy loading）
    private var loadedIndices = Set<Int>()

    /// 切換集數／重建 scrollView 時設為 true，忽略 scroll delegate callback
    /// 避免 contentSize 變動時 scroll view 觸發的 callback 覆蓋 currentIndex
    private var isRebuildingScrollView = false

    /// 超出當前頁前後幾頁的圖片會被釋放，避免讀到後面時記憶體一路累積
    private let keepRange = 4

    private let retryStrategy = DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2))

    /// 某一頁圖片對應到哪些 imageView（循環模式的首尾複製頁也要一起處理）
    private func viewIndices(forImageIndex imageIndex: Int) -> [Int]
    {
        guard allowCircular else { return [imageIndex] }
        var indices = [imageIndex + 1]
        // 第 0 個 view 是最後一頁的複製、最後一個 view 是第一頁的複製
        if imageIndex == images.count - 1 { indices.append(0) }
        if imageIndex == 0 { indices.append(images.count + 1) }
        return indices
    }

    func loadVisibleImages()
    {
        guard images.count > 0 else { return }
        guard let referer = episodeUrl else { return }

        releaseFarImages()

        var options: KingfisherOptionsInfo = [.transition(ImageTransition.fade(1)),
                                              .requestModifier(WLComics.sharedInstance().buildDownloadEpisodeHeader(referer)),
                                              .retryStrategy(retryStrategy),
                                              // 原圖也存進快取，讓 iPad 左側縮圖可以共用，不必重新下載
                                              .cacheOriginalImage]
        // 依畫面大小降採樣，避免每頁都以原尺寸解碼常駐記憶體
        let side = max(bounds.width, bounds.height)
        if side > 0 {
            options.append(.processor(DownsamplingImageProcessor(size: CGSize(width: side, height: side))))
            options.append(.scaleFactor(UIScreen.main.scale))
        }
        let placeholder = UIImage(named: "comic_place_holder")

        // 下載連線只有 2 條，當前頁要排第一個，接著往後讀的方向，最後才是前面的頁
        // 雙頁模式下當前畫面有兩頁，預載範圍也以「組」為單位放大
        let pps = pagesPerSpread
        let span = prefetchRange * pps
        var order = Array(currentIndex..<(currentIndex + pps))
        for offset in 0..<span { order.append(currentIndex + pps + offset) }
        for offset in 1...span { order.append(currentIndex - offset) }

        for imageIndex in order where imageIndex >= 0 && imageIndex < images.count {
            if loadedIndices.contains(imageIndex) { continue }
            guard let url = URL(string: images[imageIndex]) else { continue }
            loadedIndices.insert(imageIndex)

            for viewIndex in viewIndices(forImageIndex: imageIndex) where viewIndex < imageViewArray.count {
                imageViewArray[viewIndex].kf.setImage(with: url, placeholder: placeholder, options: options) { [weak self] result in
                    if case .failure = result { self?.loadedIndices.remove(imageIndex) }
                }
            }
        }
    }

    /// 釋放離當前頁太遠的圖片並取消其下載；之後滑回來會從 Kingfisher 快取快速取回
    private func releaseFarImages()
    {
        let placeholder = UIImage(named: "comic_place_holder")
        let range = keepRange * pagesPerSpread
        let farIndices = loadedIndices.filter { abs($0 - currentIndex) > range }
        for imageIndex in farIndices {
            loadedIndices.remove(imageIndex)
            for viewIndex in viewIndices(forImageIndex: imageIndex) where viewIndex < imageViewArray.count {
                let imageV = imageViewArray[viewIndex]
                imageV.kf.cancelDownloadTask()
                imageV.image = placeholder
            }
        }
    }
    
    func getImageView(index : Int)-> UIImageView
    {
        if index < imageViewArray.count
        {
            return imageViewArray[index]
        }
        
        let imageV = UIImageView()
        imageV.contentMode = .scaleAspectFit
        imageV.clipsToBounds = true
        imageV.isUserInteractionEnabled = true
        let tapOnImage = UITapGestureRecognizer(target: self, action: #selector(self.tapOnImage))
        imageV.addGestureRecognizer(tapOnImage)
        imageViewArray.append(imageV)
        return imageV
    }
    
    func createSlider(withImages images: [String], withAutoScroll isAutoScrollEnabled: Bool, in parentView: UIView)
    {
        self.frame = UIScreen.main.bounds
        self.images = images
        autoSrcollEnabled = isAutoScrollEnabled
    }
    
    @objc func tapOnImage(gesture: UITapGestureRecognizer){
        delegate?.sliderImageTapped(slider: self, index: currentIndex)
    }
    
    func getCurrentIndex()->Int
    {
        let width: CGFloat = myScrollView.frame.size.width
        return Int((myScrollView.contentOffset.x + (0.5 * width)) / width)
    }
    
    func getCurrentIndex(x : CGFloat)->Int
    {
        let width: CGFloat = myScrollView.frame.size.width
        return Int((x + (0.5 * width)) / width)
    }
    
    //#pragma mark - UIScrollView delegate
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if isRebuildingScrollView { return }
        lastIndex = getCurrentIndex()
        self.invalidateTimer()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if isRebuildingScrollView { return }
        let index = getCurrentIndex(x: targetContentOffset.pointee.x)

        // 非循環模式：在邊界頁面滑動時，UIScrollView 會 clamp offset 導致 index == lastIndex
        // 所以需要在 index != lastIndex 判斷之外額外檢查邊界滑動
        if !allowCircular && index == lastIndex && images.count > 0 {
            if isOnLastSpread && velocity.x > 0 {
                onSwipePastLastPage?()
                return
            } else if currentIndex == 0 && velocity.x < 0 {
                onSwipePastFirstPage?()
                return
            }
        }

        if index != lastIndex
        {
            currentIndex = index
            if allowCircular
            {
                currentIndex = index - 1
                if currentIndex < 0 {
                    currentIndex = images.count - 1
                }else if currentIndex > images.count - 1
                {
                    currentIndex = 0
                }
            }
            else
            {
                // 非循環模式：滑過最後一頁往右 → 下一話，滑過第一頁往左 → 上一話
                if index >= spreadCount && velocity.x > 0 {
                    currentIndex = (spreadCount - 1) * pagesPerSpread
                    targetContentOffset.pointee.x = getActualOffsetFor(index: spreadCount - 1)
                    onSwipePastLastPage?()
                    return
                } else if index < 0 && velocity.x < 0 {
                    currentIndex = 0
                    targetContentOffset.pointee.x = 0
                    onSwipePastFirstPage?()
                    return
                }
                let slot = min(max(index, 0), max(spreadCount - 1, 0))
                currentIndex = slot * pagesPerSpread
                adjustContentOffsetFor(index: currentIndex, offsetIndex: slot, animated: true)
                return
            }
            adjustContentOffsetFor(index: currentIndex, offsetIndex: index, animated: true)
        }
    }

    /// 停在新的一頁時回報頁碼（雙頁模式回報該組的第一頁），用來記錄閱讀進度
    var onPageChanged: ((Int) -> Void)?
    private var lastReportedPage = -1

    private func reportPageIfChanged()
    {
        guard images.count > 0, currentIndex != lastReportedPage else { return }
        lastReportedPage = currentIndex
        onPageChanged?(currentIndex)
    }

    /// 跳到指定頁（雙頁模式會對齊到該頁所在的那一組）
    func scrollToPage(_ page: Int, animated: Bool = true)
    {
        guard images.count > 0 else { return }
        let target = min(max(page, 0), images.count - 1)
        currentIndex = target - target % pagesPerSpread
        adjustContentOffsetFor(index: currentIndex, offsetIndex: convertIndex(), animated: animated)
    }

    // 滑過邊界時的 callback
    var onSwipePastLastPage: (() -> Void)?
    var onSwipePastFirstPage: (() -> Void)?
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if isRebuildingScrollView { return }
        let index = getCurrentIndex()
        if allowCircular {
            currentIndex = index - 1
            if currentIndex < 0 { currentIndex = images.count - 1 }
            else if currentIndex > images.count - 1 { currentIndex = 0 }
        } else {
            currentIndex = min(max(index, 0), max(spreadCount - 1, 0)) * pagesPerSpread
        }
        // 滑動換頁後也要更新箭頭按鈕的啟用狀態，否則會停留在上一頁的判斷結果
        checkButtonsIfNeedsDisable()
        loadVisibleImages()
        reportPageIfChanged()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if isRebuildingScrollView { return }
        if allowCircular && images.count != 0
        {
            if (currentIndex == 0 && myScrollView.contentOffset.x != getOffsetFor(index: 0)) || ((currentIndex == (images.count - 1)) && myScrollView.contentOffset.x != getOffsetFor(index: (images.count - 1)))
            {
                adjustContentOffsetFor(index: currentIndex, offsetIndex: convertIndex(), animated: false)
            }
        }
    }
    
    private func getOffsetFor(index : Int)->CGFloat
    {
        var tempIndex = index
        if allowCircular
        {
            tempIndex += 1
        }
        return CGFloat(tempIndex)*bounds.width
    }
    
    private func getActualOffsetFor(index : Int)->CGFloat
    {
        return CGFloat(index)*bounds.width
    }
    
    //pragma mark end
    @objc func slideImage()
    {
        let previous = currentIndex
        currentIndex = currentIndex + 1
        var convertedIndex = convertIndex()
        if currentIndex > images.count - 1 {
            if allowCircular {
                currentIndex = 0
            }
            else
            {
                currentIndex = previous
                convertedIndex = convertIndex()
            }
            
        }
        adjustContentOffsetFor(index: currentIndex, offsetIndex: convertedIndex, animated: true)
    }
    
    func checkForAutoScrolled()
    {
        if(images.count > 1 && autoSrcollEnabled){
            self .startTimerThread()
        }
        else
        {
            invalidateTimer()
        }
    }
    
    func startTimerThread()
    {
        invalidateTimer()
        activeTimer = Timer.scheduledTimer(timeInterval: durationTime, target: self, selector: #selector(self.slideImage), userInfo: nil, repeats: true)
    }
    
    func startAutoPlay() {
        autoSrcollEnabled = true
    }
    
    func stopAutoPlay() {
        autoSrcollEnabled =  false
        invalidateTimer()
    }
    
    func invalidateTimer()
    {
        if activeTimer != nil
        {
            activeTimer!.invalidate()
            activeTimer = nil
        }
    }
    
    /// 目前是否停在最後一頁（雙頁模式下是最後一組）
    private var isOnLastSpread : Bool {
        return currentIndex + pagesPerSpread > images.count - 1
    }

    private func checkButtonsIfNeedsDisable()
    {
        checkIfPrevNeedsDisable()
        checkIfNextNeedsDisable()
    }
    
    private func checkIfNextNeedsDisable()
    {
        if !allowCircular && isOnLastSpread  {
            nextArrowButton.isEnabled = false
        }
        else
        {
            nextArrowButton.isEnabled = true
        }
    }
    
    private func checkIfPrevNeedsDisable()
    {
        if !allowCircular && currentIndex == 0
        {
            prevArrowButton.isEnabled = false
        }
        else
        {
            prevArrowButton.isEnabled = true
        }
    }
    
    @IBAction func nextButtonPressed()
    {
        invalidateTimer()
        guard images.count > 0 else { return }

        if allowCircular {
            // 循環模式：先捲到尾端的複製頁，再由 scrollViewDidEndScrollingAnimation 接回開頭，
            // 所以 offsetIndex 要用夾限前的值
            currentIndex += 1
            let convertedIndex = convertIndex()
            if currentIndex > images.count - 1 {
                currentIndex = 0
            }
            adjustContentOffsetFor(index: currentIndex, offsetIndex: convertedIndex, animated: true)
        } else {
            // 非循環模式：已在最後一頁就換下一話，與滑動到底的行為一致，不繞回第一頁
            guard !isOnLastSpread else {
                onSwipePastLastPage?()
                return
            }
            currentIndex += pagesPerSpread
            adjustContentOffsetFor(index: currentIndex, offsetIndex: convertIndex(), animated: true)
        }
    }

    @IBAction func previousButtonPressed()
    {
        invalidateTimer()
        guard images.count > 0 else { return }

        if allowCircular {
            currentIndex -= 1
            let convertedIndex = convertIndex()
            if currentIndex < 0 {
                currentIndex = images.count - 1
            }
            adjustContentOffsetFor(index: currentIndex, offsetIndex: convertedIndex, animated: true)
        } else {
            // 非循環模式：已在第一頁就換上一話
            guard currentIndex > 0 else {
                onSwipePastFirstPage?()
                return
            }
            currentIndex = max(currentIndex - pagesPerSpread, 0)
            adjustContentOffsetFor(index: currentIndex, offsetIndex: convertIndex(), animated: true)
        }
    }
}


public struct CPButtonConfig
{
    var width : CGFloat = 30
    var height : CGFloat = 30
    var cornerRadius : CGFloat = 15
}
