//
//  TVReaderViewController.swift
//  WLTVComics
//
//  全螢幕閱讀器 — 支援左右翻頁（日漫）與上下捲動（條漫）
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

    // MARK: - 水平模式（翻頁）
    private let imageView = UIImageView()

    // MARK: - 直式模式（上下捲動）
    private let verticalReader = VerticalReaderView()
    private var currentMode: ReadingMode = .horizontal
    /// 直式閱讀的欄寬佔畫面寬度的比例
    private static let verticalWidthRatio: CGFloat = 0.55

    private let pageLabel = UILabel()
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

        setUpImageView()
        setUpVerticalReader()
        setUpOverlayLabels()
        setUpActivityIndicator()
        setUpGestures()
        applyMode()
    }

    // MARK: - UI Setup

    private func setUpImageView() {
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
            self.pageLabel.text = "  \(page + 1) / \(self.displayedImages.count)  "
            if let comicId = self.comicId, let url = self.displayedEpisodeUrl {
                ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: self.displayedEpisodeName, page: page)
            }
        }
        verticalReader.onSwipePastLastPage = { [weak self] in self?.loadNextEpisode() }
        verticalReader.onSwipePastFirstPage = { [weak self] in self?.loadPreviousEpisode() }
        verticalReader.onTap = { [weak self] in self?.handleTap() }
    }

    private func setUpOverlayLabels() {
        pageLabel.font = .systemFont(ofSize: 32, weight: .bold)
        pageLabel.textColor = .white
        pageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        pageLabel.layer.cornerRadius = 8
        pageLabel.clipsToBounds = true
        pageLabel.textAlignment = .center
        pageLabel.alpha = 0
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageLabel)

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
            pageLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            pageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            pageLabel.heightAnchor.constraint(equalToConstant: 50),
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
    }

    // MARK: - 閱讀模式切換

    private func applyMode() {
        imageView.isHidden = currentMode == .vertical
        verticalReader.isHidden = currentMode == .horizontal
    }

    private func toggleMode() {
        let newMode: ReadingMode = currentMode == .horizontal ? .vertical : .horizontal
        currentMode = newMode
        if let id = comicId {
            ReadingModeStore.setManual(newMode, for: id)
        }
        applyMode()
        showCurrentContent()

        modeLabel.attributedText = modeText(for: currentMode)
        modeLabel.alpha = 1
        UIView.animate(withDuration: 0.5, delay: 1.5) {
            self.modeLabel.alpha = 0
        }
    }

    /// 模式提示：上下箭頭圖示代表直式閱讀，左右箭頭圖示代表翻頁閱讀
    private func modeText(for mode: ReadingMode) -> NSAttributedString {
        let symbolName = mode == .vertical ? "arrow.up.and.down" : "arrow.left.and.right"
        let title = mode == .vertical ? "直式閱讀" : "翻頁閱讀"
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
            imageView.kf.cancelDownloadTask()
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

    private func loadCurrentPage() {
        guard currentPage >= 0, currentPage < displayedImages.count else { return }
        let urlStr = displayedImages[currentPage]
        guard let url = URL(string: urlStr) else { return }

        imageView.kf.cancelDownloadTask()
        imageView.kf.setImage(with: url,
                              options: [.requestModifier(refererModifier),
                                        .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))])

        pageLabel.text = "  \(currentPage + 1) / \(displayedImages.count)  "
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
                // 播放/暫停鍵切換閱讀模式
                toggleMode()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    private func goNextPage() {
        if currentMode == .vertical {
            verticalReader.nextButtonPressed()
            return
        }
        showOverlayBriefly()
        if currentPage < displayedImages.count - 1 {
            currentPage += 1
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
        if currentPage > 0 {
            currentPage -= 1
            loadCurrentPage()
        } else {
            loadPreviousEpisode()
        }
    }

    @objc private func handleTap() {
        let isVisible = pageLabel.alpha > 0
        UIView.animate(withDuration: 0.3) {
            self.pageLabel.alpha = isVisible ? 0 : 1
            self.episodeLabel.alpha = isVisible ? 0 : 1
        }
        if !isVisible { scheduleHideTimer() }
    }

    private func showOverlayBriefly() {
        UIView.animate(withDuration: 0.2) {
            self.pageLabel.alpha = 1
            self.episodeLabel.alpha = 1
        }
        scheduleHideTimer()
    }

    private func scheduleHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.5) {
                self?.pageLabel.alpha = 0
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

    // MARK: - Focus

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [view]
    }
}
