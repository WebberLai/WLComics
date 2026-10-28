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

        setUpActivityIndicator()
        loadEpisodes()

        // 加入「繼續閱讀」按鈕
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "繼續閱讀", style: .plain,
                                                             target: self, action: #selector(continueReading))
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        activityIndicator.startAnimating()
        WLComics.sharedInstance().getR8Comic().loadComicDetail(currentComic) { [weak self] comicDetail in
            let episodes = comicDetail.getEpisode()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.allEpisodes = episodes
                self.refreshLastRead()
                self.activityIndicator.stopAnimating()
                self.tableView.reloadData()
                self.navigationItem.rightBarButtonItem?.isEnabled = self.lastReadIndex != nil
                self.scrollToLastRead()
            }
        }
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
