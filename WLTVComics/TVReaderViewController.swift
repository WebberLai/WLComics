//
//  TVReaderViewController.swift
//  WLTVComics
//
//  全螢幕閱讀器 — 支援雙頁翻頁（日漫右翻左／美漫左翻右）與上下捲動（條漫）
//

import UIKit
import Kingfisher

class TVReaderViewController: UIViewController {

    var allEpisodes = [Episode]()
    var comicId: String?
    var episodeIndex: Int = 0

    private var displayedImages = [String]()
    private var displayedEpisodeUrl: String?
    private var displayedEpisodeName = ""

    // MARK: - 水平模式（翻頁，一次兩頁）
    private let spreadView = TVSpreadView()
    /// 美漫（左翻右）順序；預設 false 為日漫順序。只存在本機，不同步
    private var isLeftToRight = false
    private var prefetcher: ImagePrefetcher?

    // MARK: - 直式模式（上下捲動）
    private let verticalReader = VerticalReaderView()
    private var currentMode: ReadingMode = .horizontal
    /// 直式閱讀的欄寬佔畫面寬度的比例
    private static let verticalWidthRatio: CGFloat = 0.55

    private let episodeLabel = UILabel()
    private let modeLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private var currentPage = 0
    private var hideTimer: Timer?

    private var refererModifier: AnyModifier {
        let url = displayedEpisodeUrl ?? "https://www.8comic.com/"
        return AnyModifier { request in
            var r = request
            r.setValue(url, forHTTPHeaderField: "Referer")
            return r
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // 讀取該漫畫存過的閱讀模式
        if let id = comicId, let saved = ReadingModeStore.mode(for: id) {
            currentMode = saved
        }
        if let id = comicId {
            isLeftToRight = TVReaderViewController.isLeftToRight(comicId: id)
        }

        setUpImageView()
        setUpVerticalReader()
        setUpOverlayLabels()
        setUpActivityIndicator()
        setUpGestures()
        applyMode()
    }

    // MARK: - UI Setup

    private func setUpImageView() {
        spreadView.backgroundColor = .black
        spreadView.isRightToLeft = !isLeftToRight
        spreadView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spreadView)
        NSLayoutConstraint.activate([
            spreadView.topAnchor.constraint(equalTo: view.topAnchor),
            spreadView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spreadView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            spreadView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setUpVerticalReader() {
        verticalReader.translatesAutoresizingMaskIntoConstraints = false
        verticalReader.backgroundColor = .black
        view.addSubview(verticalReader)
        // 條漫原圖多半只有 700–800 px 寬，塞滿電視寬度會放大到糊掉、一個畫面也看不到多少，
        // 所以限制成畫面寬度的一部分並置中
        NSLayoutConstraint.activate([
            verticalReader.topAnchor.constraint(equalTo: view.topAnchor),
            verticalReader.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            verticalReader.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            verticalReader.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: TVReaderViewController.verticalWidthRatio),
        ])

        verticalReader.onPageChanged = { [weak self] page in
            guard let self = self else { return }
            self.currentPage = page
            if let comicId = self.comicId, let url = self.displayedEpisodeUrl {
                ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: self.displayedEpisodeName, page: page)
            }
        }
        verticalReader.onSwipePastLastPage = { [weak self] in self?.loadNextEpisode() }
        verticalReader.onSwipePastFirstPage = { [weak self] in self?.loadPreviousEpisode() }
        verticalReader.onTap = { [weak self] in self?.handleTap() }
    }

    private func setUpOverlayLabels() {
        episodeLabel.font = .systemFont(ofSize: 36, weight: .bold)
        episodeLabel.textColor = .white
        episodeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        episodeLabel.layer.cornerRadius = 8
        episodeLabel.clipsToBounds = true
        episodeLabel.textAlignment = .center
        episodeLabel.alpha = 0
        episodeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(episodeLabel)

        // 閱讀模式提示（右上）
        modeLabel.font = .systemFont(ofSize: 28, weight: .medium)
        modeLabel.textColor = .white
        modeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        modeLabel.layer.cornerRadius = 8
        modeLabel.clipsToBounds = true
        modeLabel.textAlignment = .center
        modeLabel.alpha = 0
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeLabel)

        NSLayoutConstraint.activate([
            episodeLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            episodeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            episodeLabel.heightAnchor.constraint(equalToConstant: 56),
            modeLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            modeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            modeLabel.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setUpActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setUpGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeUp.direction = .up
        view.addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)

        // 長按觸控板中間：開閱讀模式選單
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { presentModeMenu() }
    }

    // MARK: - 閱讀模式切換

    private func applyMode() {
        spreadView.isHidden = currentMode == .vertical
        verticalReader.isHidden = currentMode == .horizontal
        spreadView.isRightToLeft = !isLeftToRight
    }

    /// 播放/暫停鍵或長按中間鍵：選日漫翻頁、美漫翻頁、韓漫直式
    private func presentModeMenu() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "閱讀模式", message: nil, preferredStyle: .actionSheet)
        let choices: [(String, ReadingMode, Bool)] = [
            ("日漫翻頁（右→左）", .horizontal, false),
            ("美漫翻頁（左→右）", .horizontal, true),
            ("韓漫直式（上→下）", .vertical, false),
        ]
        for (title, mode, leftToRight) in choices {
            let isCurrent = mode == currentMode && (mode == .vertical || leftToRight == isLeftToRight)
            alert.addAction(UIAlertAction(title: isCurrent ? "✓ \(title)" : title, style: .default) { [weak self] _ in
                self?.setMode(mode, leftToRight: leftToRight)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func setMode(_ mode: ReadingMode, leftToRight: Bool) {
        let modeChanged = mode != currentMode
        currentMode = mode
        // 直式時保留原本的翻頁方向，切回翻頁才不會被重設
        if mode == .horizontal { isLeftToRight = leftToRight }
        if let id = comicId {
            ReadingModeStore.setManual(mode, for: id)
            TVReaderViewController.setLeftToRight(isLeftToRight, comicId: id)
        }
        applyMode()
        if modeChanged || mode == .horizontal { showCurrentContent() }
        showModeLabel()
    }

    private func showModeLabel() {
        modeLabel.layer.removeAllAnimations()
        modeLabel.attributedText = modeText(for: currentMode)
        modeLabel.alpha = 1
        UIView.animate(withDuration: 0.5, delay: 2.5) {
            self.modeLabel.alpha = 0
        }
    }

    /// 模式提示：上下箭頭圖示代表直式閱讀，左右箭頭圖示代表翻頁閱讀
    private func modeText(for mode: ReadingMode) -> NSAttributedString {
        let symbolName = mode == .vertical ? "arrow.up.and.down" : "arrow.left.and.right"
        let title = mode == .vertical ? "韓漫直式" : (isLeftToRight ? "美漫翻頁（左→右）" : "日漫翻頁（右→左）")
        let config = UIImage.SymbolConfiguration(font: modeLabel.font)
        let text = NSMutableAttributedString(string: "  ")
        if let image = UIImage(systemName: symbolName, withConfiguration: config)?
            .withTintColor(modeLabel.textColor, renderingMode: .alwaysOriginal) {
            text.append(NSAttributedString(attachment: NSTextAttachment(image: image)))
            text.append(NSAttributedString(string: " "))
        }
        text.append(NSAttributedString(string: "\(title)  "))
        return text
    }

    /// 在模式切換後，用目前的 page 重新顯示
    private func showCurrentContent() {
        if currentMode == .horizontal {
            verticalReader.cancelAllDownloads()
            loadCurrentPage()
        } else {
            spreadView.cancelDownloads()
            prefetcher?.stop()
            verticalReader.episodeUrl = displayedEpisodeUrl
            verticalReader.currentIndex = currentPage
            verticalReader.images = displayedImages
        }
    }

    // MARK: - Episode Loading

    func loadEpisode(at index: Int, startPage: Int = 0) {
        guard index >= 0, index < allEpisodes.count else { return }
        episodeIndex = index
        let episode = allEpisodes[index]

        activityIndicator.startAnimating()

        WLComics.sharedInstance().loadEpisodeDetail(episode) { [weak self] episode in
            DispatchQueue.main.async {
                guard let self = self, self.episodeIndex == index else { return }
                episode.setUpPages()
                let pages = episode.getImageUrlList()
                self.displayedEpisodeUrl = episode.getUrl()
                self.displayedEpisodeName = episode.getName()
                self.displayedImages = pages
                self.currentPage = min(max(startPage, 0), max(pages.count - 1, 0))
                self.activityIndicator.stopAnimating()

                if self.currentMode == .horizontal {
                    self.loadCurrentPage()
                } else {
                    self.verticalReader.episodeUrl = episode.getUrl()
                    self.verticalReader.currentIndex = self.currentPage
                    self.verticalReader.images = pages
                }
                self.showOverlayBriefly()
            }
        }
    }

    /// 顯示 currentPage 開始的跨頁。currentPage 一律對齊到偶數（跨頁的第一頁）
    private func loadCurrentPage() {
        guard currentPage >= 0, currentPage < displayedImages.count else { return }
        currentPage -= currentPage % 2
        let count = displayedImages.count
        let firstUrl = URL(string: displayedImages[currentPage])
        let hasSecond = currentPage + 1 < count
        let secondUrl = hasSecond ? URL(string: displayedImages[currentPage + 1]) : nil

        let options: KingfisherOptionsInfo = [.requestModifier(refererModifier),
                                              .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))]
        spreadView.isRightToLeft = !isLeftToRight
        // 最後一頁落單時 secondUrl 為 nil，另一半留空白
        spreadView.show(first: firstUrl, second: secondUrl, options: options)

        // 預載下一個跨頁
        prefetcher?.stop()
        let nextUrls = displayedImages.dropFirst(currentPage + 2).prefix(2).compactMap { URL(string: $0) }
        if !nextUrls.isEmpty {
            prefetcher = ImagePrefetcher(urls: nextUrls, options: [.requestModifier(refererModifier)])
            prefetcher?.start()
        }

        episodeLabel.text = "  \(displayedEpisodeName)  "

        if let comicId = comicId, let url = displayedEpisodeUrl {
            ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: displayedEpisodeName, page: currentPage)
        }
    }

    // MARK: - Gestures & Press Events

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .left:  goNextPage()
        case .right: goPreviousPage()
        // 和按觸控板上下緣一致：往下是往後讀
        case .down:
            if currentMode == .vertical { verticalReader.nextButtonPressed() }
        case .up:
            if currentMode == .vertical { verticalReader.previousButtonPressed() }
        default: break
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .rightArrow:
                goNextPage()
                return
            case .leftArrow:
                goPreviousPage()
                return
            case .upArrow:
                if currentMode == .vertical { verticalReader.previousButtonPressed() }
                return
            case .downArrow:
                if currentMode == .vertical { verticalReader.nextButtonPressed() }
                return
            case .select:
                handleTap()
                return
            case .menu:
                dismiss(animated: true)
                return
            case .playPause:
                // 播放/暫停鍵開閱讀模式選單
                presentModeMenu()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    // pressesBegan 自己處理掉的鍵，Ended / Changed / Cancelled 也要一起攔住，
    // 否則放開返回鍵時事件會沿 responder chain 傳到底下的 navigation controller，
    // 在 dismiss 的同時又 pop 一層，畫面就變黑
    private static let handledPressTypes: Set<UIPress.PressType> = [
        .rightArrow, .leftArrow, .upArrow, .downArrow, .select, .menu, .playPause,
    ]

    private func unhandled(_ presses: Set<UIPress>) -> Set<UIPress> {
        return presses.filter { !TVReaderViewController.handledPressTypes.contains($0.type) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = unhandled(presses)
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = unhandled(presses)
        if !rest.isEmpty { super.pressesChanged(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = unhandled(presses)
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }

    private func goNextPage() {
        if currentMode == .vertical {
            verticalReader.nextButtonPressed()
            return
        }
        showOverlayBriefly()
        if currentPage + 2 < displayedImages.count {
            currentPage += 2
            loadCurrentPage()
        } else {
            loadNextEpisode()
        }
    }

    private func goPreviousPage() {
        if currentMode == .vertical {
            verticalReader.previousButtonPressed()
            return
        }
        showOverlayBriefly()
        if currentPage >= 2 {
            currentPage -= 2
            loadCurrentPage()
        } else {
            loadPreviousEpisode()
        }
    }

    @objc private func handleTap() {
        let isVisible = episodeLabel.alpha > 0
        UIView.animate(withDuration: 0.3) {
            self.episodeLabel.alpha = isVisible ? 0 : 1
        }
        if !isVisible { scheduleHideTimer() }
    }

    private func showOverlayBriefly() {
        UIView.animate(withDuration: 0.2) {
            self.episodeLabel.alpha = 1
        }
        scheduleHideTimer()
    }

    private func scheduleHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.5) {
                self?.episodeLabel.alpha = 0
            }
        }
    }

    // MARK: - Episode Navigation

    private func loadNextEpisode() {
        guard episodeIndex < allEpisodes.count - 1 else { return }
        loadEpisode(at: episodeIndex + 1)
    }

    private func loadPreviousEpisode() {
        guard episodeIndex > 0 else { return }
        loadEpisode(at: episodeIndex - 1)
    }

    // MARK: - 翻頁方向（本機）

    private static let leftToRightKey = "tv_left_to_right_comics"

    static func isLeftToRight(comicId: String) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: leftToRightKey) ?? []
        return ids.contains(comicId)
    }

    static func setLeftToRight(_ value: Bool, comicId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: leftToRightKey) ?? []
        ids.removeAll { $0 == comicId }
        if value { ids.append(comicId) }
        UserDefaults.standard.set(ids, forKey: leftToRightKey)
    }

    // MARK: - Focus

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [view]
    }
}
