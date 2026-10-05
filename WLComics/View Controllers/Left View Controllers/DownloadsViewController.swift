//
//  DownloadsViewController.swift
//  WLComics
//

import UIKit
import Swift8ComicSDK
import Kingfisher

/// 「已下載」tab：列出有下載內容的漫畫，離線時從這裡進入閱讀。只能手動刪除。
class DownloadsViewController: UITableViewController {

    private var comics = [DownloadManager.ComicRecord]()
    /// 佔用空間要掃描檔案，背景算好後快取
    private var diskUsage = [String: Int64]()

    private static let coverSize = CGSize(width: 75, height: 100)

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "還沒有下載的漫畫\n在集數列表往左滑即可下載"
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "已下載"
        tableView.backgroundColor = .systemBackground
        tableView.rowHeight = 116
        // iOS 26 之後系統 cell 的分隔線預設會被隱藏或縮排到看不見，明確指定樣式與起點（與集數列表一致）
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = .separator
        tableView.separatorInsetReference = .fromCellEdges
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsDidChange),
                                               name: DownloadManager.didChangeNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc func downloadsDidChange() {
        guard isViewLoaded, view.window != nil else { return }
        reloadList()
        // 下載中每 0.3 秒就會通知一次，佔用空間等通知停下來 1 秒後再重算，避免一直掃描檔案
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshDiskUsage), object: nil)
        perform(#selector(refreshDiskUsage), with: nil, afterDelay: 1)
    }

    private func reload() {
        reloadList()
        refreshDiskUsage()
    }

    private func reloadList() {
        comics = DownloadManager.shared.downloadedComics()
        tableView.backgroundView = comics.isEmpty ? emptyLabel : nil
        tableView.reloadData()
    }

    @objc private func refreshDiskUsage() {
        let ids = comics.map { $0.comicId }
        DispatchQueue.global(qos: .utility).async {
            var usage = [String: Int64]()
            for id in ids { usage[id] = DownloadManager.shared.diskUsage(comicId: id) }
            DispatchQueue.main.async {
                self.diskUsage = usage
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Table view

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DownloadCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "DownloadCell")
        let comic = comics[indexPath.row]
        cell.textLabel?.text = comic.name
        cell.accessoryType = .disclosureIndicator

        let completed = comic.episodes.filter { $0.completed }.count
        var details = ["已下載 \(completed) 話"]
        if let bytes = diskUsage[comic.comicId] {
            details.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        if DownloadManager.shared.isDownloading(comicId: comic.comicId) {
            details.append("下載中")
        }
        cell.detailTextLabel?.text = details.joined(separator: " · ")
        cell.detailTextLabel?.textColor = .secondaryLabel

        cell.imageView?.kf.cancelDownloadTask()
        if let cover = DownloadManager.shared.coverURL(comicId: comic.comicId) {
            cell.imageView?.kf.setImage(with: cover,
                                        placeholder: UIImage(named: "comic_place_holder"),
                                        options: [.processor(DownsamplingImageProcessor(size: Self.coverSize)),
                                                  .scaleFactor(UIScreen.main.scale)])
        } else {
            cell.imageView?.image = UIImage(named: "comic_place_holder")
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let record = comics[indexPath.row]
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let episodesViewController = storyboard.instantiateViewController(withIdentifier: "ComicEpisodesViewController")
                as? ComicEpisodesViewController else { return }
        let comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(record.comicId, name: record.name)
        // 離線時封面用下載時存下的本機檔案
        if let cover = DownloadManager.shared.coverURL(comicId: record.comicId) {
            comic.setSmallIconUrl(cover.absoluteString)
        }
        episodesViewController.currentComic = comic
        episodesViewController.offlineMode = true
        episodesViewController.title = record.name
        navigationController?.pushViewController(episodesViewController, animated: true)
    }

    /// 往左滑刪除整部漫畫的下載，會再確認一次
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let record = comics[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "刪除") { _, _, done in
            let alert = UIAlertController(title: "刪除下載",
                                          message: "要刪除「\(record.name)」所有已下載的內容嗎？",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in done(false) })
            alert.addAction(UIAlertAction(title: "刪除", style: .destructive) { _ in
                DownloadManager.shared.deleteComic(comicId: record.comicId)
                done(true)
            })
            self.present(alert, animated: true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}
