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
    private let statusLabel = UILabel()

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

        tableView.register(TVEpisodeCell.self, forCellReuseIdentifier: TVEpisodeCell.reuseId)

        focusAnchor.isUserInteractionEnabled = true
        view.addSubview(focusAnchor)
        setUpActivityIndicator()
        setUpStatusLabel()
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
        activityIndicator.color = .white
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setUpStatusLabel() {
        statusLabel.text = "正在載入集數…"
        statusLabel.font = .systemFont(ofSize: 24, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.isHidden = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 24),
        ])
    }

    private func loadEpisodes() {
        updateFocusAnchor()
        activityIndicator.startAnimating()

        loadTimeoutTimer?.invalidate()
        loadTimeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.loadTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.activityIndicator.stopAnimating()
            self.statusLabel.text = "暫時無法載入集數，請返回後重試。"
        }

        WLComics.sharedInstance().getR8Comic().loadComicDetail(currentComic) { [weak self] comicDetail in
            let episodes = comicDetail.getEpisode()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadTimeoutTimer?.invalidate()
                self.allEpisodes = episodes
                self.refreshLastRead()
                self.activityIndicator.stopAnimating()
                self.statusLabel.text = episodes.isEmpty ? "目前沒有可閱讀的集數。" : nil
                self.statusLabel.isHidden = !episodes.isEmpty
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
        let cell = tableView.dequeueReusableCell(withIdentifier: TVEpisodeCell.reuseId, for: indexPath) as! TVEpisodeCell
        let episode = allEpisodes[indexPath.row]
        var subtitle: String?
        if indexPath.row == lastReadIndex, let entry = lastRead {
            subtitle = "上次看到第 \(entry.page + 1) 頁"
        }

        let coverURL = currentComic.getSmallIconUrl().flatMap { URL(string: $0) }
        cell.configure(title: episode.getName(), subtitle: subtitle,
                       coverURL: coverURL, modifier: refererModifier)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let page = indexPath.row == lastReadIndex ? (lastRead?.page ?? 0) : 0
        openEpisode(at: indexPath.row, startPage: page)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 144
    }
}

/// A wide, focusable episode card. Keeping the cover view in the reusable cell
/// lets Kingfisher update it when the asynchronous image request completes.
private final class TVEpisodeCell: UITableViewCell {
    static let reuseId = "TVEpisodeCell"

    /// tvOS 沒有 secondarySystemBackground，自己定義深灰底
    private static let cardColor = UIColor(white: 0.16, alpha: 1)

    private let cardView = UIView()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let labelsStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear
        cardView.backgroundColor = Self.cardColor
        cardView.layer.cornerRadius = 16
        cardView.layer.cornerCurve = .continuous
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 8
        coverView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        subtitleLabel.font = .systemFont(ofSize: 22, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        labelsStack.axis = .vertical
        labelsStack.alignment = .leading
        labelsStack.spacing = 8
        labelsStack.addArrangedSubview(titleLabel)
        labelsStack.addArrangedSubview(subtitleLabel)
        labelsStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(cardView)
        cardView.addSubview(coverView)
        cardView.addSubview(labelsStack)
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 76),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -76),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            coverView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            coverView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 78),
            coverView.heightAnchor.constraint(equalToConstant: 110),
            labelsStack.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 24),
            labelsStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            labelsStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String?, coverURL: URL?, modifier: ImageDownloadRequestModifier) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        coverView.kf.cancelDownloadTask()
        coverView.kf.setImage(with: coverURL,
                              placeholder: UIImage(named: "comic_place_holder"),
                              options: [.requestModifier(modifier),
                                        .processor(DownsamplingImageProcessor(size: CGSize(width: 156, height: 220))),
                                        .scaleFactor(UIScreen.main.scale)])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.kf.cancelDownloadTask()
        coverView.image = nil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.cardView.backgroundColor = self.isFocused ? .white : Self.cardColor
            self.titleLabel.textColor = self.isFocused ? .black : .label
            self.subtitleLabel.textColor = self.isFocused ? .darkGray : .secondaryLabel
        }
    }
}

/// 看不見、只在需要時能取得焦點的 view（見 TVEpisodeListViewController.focusAnchor）
final class TVFocusAnchorView: UIView {
    var isFocusable = false
    override var canBecomeFocused: Bool { isFocusable }
}
