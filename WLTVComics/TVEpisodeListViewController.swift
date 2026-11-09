//
//  TVEpisodeListViewController.swift
//  WLTVComics
//
//  集數列表 — tvOS 用 UITableView
//

import UIKit
import Kingfisher

class TVEpisodeListViewController: UITableViewController {

    var currentComic: Comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")
    private var allEpisodes = [Episode]()
    private var lastReadIndex: Int?
    private var lastRead: ReadingProgress.Entry?

    private let activityIndicator = UIActivityIndicatorView(style: .large)

    /// 列表沒有話數時（載入中、網站頁面是空的）畫面上沒有可聚焦的東西，
    /// 返回鍵會直接交給最外層，App 就退回桌面。用一個看不見的 view 接住焦點，
    /// 返回鍵才會經過 navigation controller 正常 pop
    private let focusAnchor = TVFocusAnchorView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private var loadTimeoutTimer: Timer?
    /// SDK 讀取失敗時不會呼叫 callback，等這麼久還沒回來就停掉轉圈
    private static let loadTimeout: TimeInterval = 20

    private let refererModifier = AnyModifier { request in
        var r = request
        r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        return r
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        tableView.backgroundColor = .black

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EpisodeCell")

        focusAnchor.isUserInteractionEnabled = true
        view.addSubview(focusAnchor)
        setUpActivityIndicator()
        loadEpisodes()

        // 加入「繼續閱讀」按鈕
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "繼續閱讀", style: .plain,
                                                             target: self, action: #selector(continueReading))
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 漫畫列表把 navigation bar 藏起來了，這頁要顯示才看得到「繼續閱讀」
        navigationController?.setNavigationBarHidden(false, animated: animated)
        refreshLastRead()
        tableView.reloadData()
        navigationItem.rightBarButtonItem?.isEnabled = lastReadIndex != nil
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

    private func loadEpisodes() {
        updateFocusAnchor()
        activityIndicator.startAnimating()

        loadTimeoutTimer?.invalidate()
        loadTimeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.loadTimeout, repeats: false) { [weak self] _ in
            self?.activityIndicator.stopAnimating()
        }

        WLComics.sharedInstance().getR8Comic().loadComicDetail(currentComic) { [weak self] comicDetail in
            let episodes = comicDetail.getEpisode()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadTimeoutTimer?.invalidate()
                self.allEpisodes = episodes
                self.refreshLastRead()
                self.activityIndicator.stopAnimating()
                self.tableView.reloadData()
                self.navigationItem.rightBarButtonItem?.isEnabled = self.lastReadIndex != nil
                self.scrollToLastRead()
                // 載入前焦點在錨點上，載完有話數就把焦點拉回列表
                self.updateFocusAnchor()
            }
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return allEpisodes.isEmpty ? [focusAnchor] : [tableView]
    }

    private func updateFocusAnchor() {
        focusAnchor.isFocusable = allEpisodes.isEmpty
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    // MARK: - Reading Progress

    private func refreshLastRead() {
        lastRead = ReadingProgress.progress(for: currentComic.getId())
        if let entry = lastRead {
            lastReadIndex = allEpisodes.firstIndex {
                ReadingProgress.normalizedEpisodeUrl($0.getUrl()) == entry.episodeUrl
            }
        } else {
            lastReadIndex = nil
        }
    }

    private func scrollToLastRead() {
        guard let row = lastReadIndex else { return }
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
    }

    @objc private func continueReading() {
        guard let row = lastReadIndex, let entry = lastRead else { return }
        openEpisode(at: row, startPage: entry.page)
    }

    private func openEpisode(at index: Int, startPage: Int = 0) {
        let vc = TVReaderViewController()
        vc.allEpisodes = allEpisodes
        vc.comicId = currentComic.getId()
        vc.loadEpisode(at: index, startPage: startPage)
        present(vc, animated: true)
    }

    // MARK: - Table View

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allEpisodes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EpisodeCell", for: indexPath)
        let episode = allEpisodes[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = episode.getName()
        config.textProperties.font = .systemFont(ofSize: 38)
        config.textProperties.color = .white

        if indexPath.row == lastReadIndex, let entry = lastRead {
            config.secondaryText = "上次看到第 \(entry.page + 1) 頁"
            config.secondaryTextProperties.color = .systemBlue
            cell.accessoryType = .checkmark
        } else {
            config.secondaryText = nil
            cell.accessoryType = .none
        }

        // 封面
        if let urlStr = currentComic.getSmallIconUrl(), let url = URL(string: urlStr) {
            let imageView = UIImageView()
            imageView.kf.setImage(with: url,
                                  placeholder: UIImage(named: "comic_place_holder"),
                                  options: [.requestModifier(refererModifier),
                                            .processor(DownsamplingImageProcessor(size: CGSize(width: 80, height: 110))),
                                            .scaleFactor(2.0)])
            config.image = imageView.image
        }

        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let page = indexPath.row == lastReadIndex ? (lastRead?.page ?? 0) : 0
        openEpisode(at: indexPath.row, startPage: page)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 120
    }
}

/// 看不見、只在需要時能取得焦點的 view（見 TVEpisodeListViewController.focusAnchor）
final class TVFocusAnchorView: UIView {
    var isFocusable = false
    override var canBecomeFocused: Bool { isFocusable }
}
