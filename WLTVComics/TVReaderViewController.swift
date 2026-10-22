//
//  TVReaderViewController.swift
//  WLTVComics
//
//  全螢幕閱讀器 — tvOS 用 Siri Remote 觸控板左右滑動翻頁
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

    private let imageView = UIImageView()
    private let pageLabel = UILabel()
    private let episodeLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private var currentPage = 0
    /// 隱藏 UI 的計時器
    private var hideTimer: Timer?

    /// 8comic 要求 Referer header
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

        setUpImageView()
        setUpOverlayLabels()
        setUpActivityIndicator()
        setUpGestures()
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

    private func setUpOverlayLabels() {
        // 頁碼標籤（右下）
        pageLabel.font = .systemFont(ofSize: 32, weight: .bold)
        pageLabel.textColor = .white
        pageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        pageLabel.layer.cornerRadius = 8
        pageLabel.clipsToBounds = true
        pageLabel.textAlignment = .center
        pageLabel.alpha = 0
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageLabel)

        // 集數標籤（左上）
        episodeLabel.font = .systemFont(ofSize: 36, weight: .bold)
        episodeLabel.textColor = .white
        episodeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        episodeLabel.layer.cornerRadius = 8
        episodeLabel.clipsToBounds = true
        episodeLabel.textAlignment = .center
        episodeLabel.alpha = 0
        episodeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(episodeLabel)

        NSLayoutConstraint.activate([
            pageLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            pageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            pageLabel.heightAnchor.constraint(equalToConstant: 50),
            episodeLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            episodeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            episodeLabel.heightAnchor.constraint(equalToConstant: 56),
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
        // Siri Remote 左右滑動翻頁
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)

        // 點擊顯示/隱藏頁碼資訊
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(tap)

        // Menu 按鈕關閉閱讀器
        let menu = UITapGestureRecognizer(target: self, action: #selector(handleMenu))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menu)
    }

    // MARK: - Episode Loading

    func loadEpisode(at index: Int, startPage: Int = 0) {
        guard index >= 0, index < allEpisodes.count else { return }
        episodeIndex = index
        let episode = allEpisodes[index]

        activityIndicator.startAnimating()

        WLComics.sharedInstance().loadEpisodeDetail(episode) { [weak self] episode in
            episode.setUpPages()
            let pages = episode.getImageUrlList()
            DispatchQueue.main.async {
                guard let self = self, self.episodeIndex == index else { return }
                self.displayedEpisodeUrl = episode.getUrl()
                self.displayedEpisodeName = episode.getName()
                self.displayedImages = pages
                self.currentPage = min(max(startPage, 0), max(pages.count - 1, 0))
                self.activityIndicator.stopAnimating()
                self.loadCurrentPage()
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

        // 記錄閱讀進度
        if let comicId = comicId, let url = displayedEpisodeUrl {
            ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: displayedEpisodeName, page: currentPage)
        }
    }

    // MARK: - Gestures

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        showOverlayBriefly()

        if gesture.direction == .left {
            // 下一頁
            if currentPage < displayedImages.count - 1 {
                currentPage += 1
                loadCurrentPage()
            } else {
                // 載入下一話
                loadNextEpisode()
            }
        } else if gesture.direction == .right {
            // 上一頁
            if currentPage > 0 {
                currentPage -= 1
                loadCurrentPage()
            } else {
                // 載入上一話
                loadPreviousEpisode()
            }
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

    @objc private func handleMenu() {
        dismiss(animated: true)
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
