//
//  ComicEpisodesViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/27.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Kingfisher

class ComicEpisodesViewController: UIViewController {
    
    @IBOutlet weak var tableView : UITableView!
    
    var allEpisodes = Array<Any>() as! [Episode]
    
    var currentComic : Comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")

    var index = 0

    /// 開啟集數時要從第幾頁開始（點上次看的那一集或按「繼續閱讀」時才會大於 0）
    private var startPage = 0

    private lazy var continueButton = UIBarButtonItem(title: "繼續閱讀", style: .plain, target: self, action: #selector(continueReading))

    /// 離線模式：從「已下載」進來時，集數列表改由下載紀錄還原，不連網
    var offlineMode = false

    /// 封面在 cell 中的最大尺寸：列高 116，上下各留約 8pt
    private static let coverSize = CGSize(width: 75, height: 100)

    /// 預先縮好的佔位圖，避免原尺寸佔位圖撐滿整列
    private static let coverPlaceholder: UIImage? = {
        guard let image = UIImage(named: "comic_place_holder") else { return nil }
        let scale = min(coverSize.width / image.size.width, coverSize.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }()

    /// 8comic 會擋掉沒有 Referer 的圖片請求，快取一份避免每個 cell 重建
    private let refererModifier = AnyModifier { request in
        var r = request
        r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        return r
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if offlineMode {
            allEpisodes = DownloadManager.shared.downloadedEpisodes(comicId: currentComic.getId())
            refreshLastRead()
            tableView.reloadData()
            updateContinueButton()
            scrollToLastRead()
        } else {
            WLComics.sharedInstance().getR8Comic().loadComicDetail(currentComic) { (comicDetail : Comic) in
                let episodes = comicDetail.getEpisode()
                DispatchQueue.main.async {
                    self.allEpisodes = episodes
                    // 看過集數列表就清掉 NEW 標記（只追蹤收藏的漫畫；0 集時 markSeen 會忽略）
                    if FavoriteComics.checkComicIsMyFavorite(self.currentComic) {
                        UpdateTracker.markSeen(comicId: self.currentComic.getId(), episodeCount: episodes.count)
                    }
                    self.refreshLastRead()
                    self.tableView.reloadData()
                    self.updateContinueButton()
                    self.scrollToLastRead()
                }
            }
        }
        self.tableView.tableHeaderView = nil
        view.backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        // iOS 26 之後系統 cell 的分隔線預設會被隱藏或縮排到看不見，明確指定樣式與起點
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = .separator
        tableView.separatorInsetReference = .fromCellEdges
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        continueButton.isEnabled = false
        var barItems = [UIBarButtonItem.init(barButtonSystemItem: .fastForward , target: self, action: #selector(scrollToBottom)),
                        continueButton]
        if !offlineMode {
            barItems.append(UIBarButtonItem(image: UIImage(systemName: "arrow.down.circle"), style: .plain,
                                            target: self, action: #selector(downloadAll)))
        }
        navigationItem.rightBarButtonItems = barItems
        // 其他裝置同步過來的進度也要反映在列表上
        NotificationCenter.default.addObserver(self, selector: #selector(progressDidChange),
                                               name: ReadingProgress.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsDidChange(_:)),
                                               name: DownloadManager.didChangeNotification, object: nil)
    }

    // MARK: - 下載

    @objc func downloadsDidChange(_ notification: Notification) {
        guard notification.userInfo?["comicId"] as? String == currentComic.getId() else { return }
        if offlineMode {
            // 離線列表只列已下載完成的集數，刪除後要重建
            allEpisodes = DownloadManager.shared.downloadedEpisodes(comicId: currentComic.getId())
            refreshLastRead()
            updateContinueButton()
        }
        tableView.reloadData()
    }

    @objc func downloadAll() {
        guard !allEpisodes.isEmpty else { return }
        let alert = UIAlertController(title: "下載全部",
                                      message: "要下載全部 \(allEpisodes.count) 話嗎？已下載的會略過。\n下載的內容只能手動刪除。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "下載", style: .default) { _ in
            DownloadManager.shared.download(comic: self.currentComic,
                                            episodes: self.allEpisodes.enumerated().map { (episode: $1, order: $0) })
        })
        present(alert, animated: true)
    }

    private func downloadStatusText(for episode: Episode) -> String? {
        switch DownloadManager.shared.state(comicId: currentComic.getId(), episodeUrl: episode.getUrl()) {
        case .none: return nil
        case .queued: return "等待下載"
        case .downloading(let progress): return "下載中 \(Int(progress * 100))%"
        case .downloaded: return "已下載"
        case .incomplete: return "下載未完成"
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 從閱讀器回來時進度已經變了
        progressDidChange()
    }

    @objc func progressDidChange() {
        refreshLastRead()
        tableView.reloadData()
        updateContinueButton()
    }

    // MARK: - 閱讀進度

    private var lastRead: ReadingProgress.Entry?
    /// 上次看的那一集在列表中的位置；網站更新後集數可能變動，所以用網址比對
    private var lastReadIndex: Int?

    /// 重新讀取進度並快取，避免每個 cell 都讀一次 UserDefaults 並掃描整個集數列表
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

    private func updateContinueButton() {
        continueButton.isEnabled = lastReadIndex != nil
    }

    private func scrollToLastRead() {
        guard let row = lastReadIndex else { return }
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
    }

    @objc func continueReading() {
        guard let row = lastReadIndex, let entry = lastRead else { return }
        openEpisode(at: row, startPage: entry.page)
    }

    private func openEpisode(at row: Int, startPage: Int) {
        index = row
        self.startPage = startPage
        if UIDevice.current.model.description == "iPad" {
            self.performSegue(withIdentifier: "showEpisodeDetail", sender: self)
        }
        else if UIDevice.current.model.description == "iPhone"{
            self.performSegue(withIdentifier: "showPageDetail", sender: self)
        }
    }
    
    @objc func scrollToBottom (){
        if self.allEpisodes.count == 0 {
            return
        }
        tableView.scrollToRow(at: IndexPath.init(item: allEpisodes.count-1 , section: 0), at: .bottom , animated: true)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showEpisodeDetail" {
            // 「繼續閱讀」不會選取 row，一律用 index
            let episode = allEpisodes[index]
            let episodeDetailViewController = segue.destination as! EpisodeDetailViewController
            episodeDetailViewController.currentEpisode = episode
            episodeDetailViewController.title = episode.getName()
            episodeDetailViewController.allEpisodes = self.allEpisodes
            episodeDetailViewController.episodeIndex = index
            episodeDetailViewController.comicId = currentComic.getId()
            episodeDetailViewController.startPage = startPage
        }else if segue.identifier == "showPageDetail" {
            let navController = segue.destination as! UINavigationController
            let pageDetailViewController = navController.viewControllers[0] as! DetailViewController

            // 傳入所有集數和當前 index，讓 DetailViewController 能自動切換上下話
            pageDetailViewController.allEpisodes = self.allEpisodes
            pageDetailViewController.comicId = currentComic.getId()
            // 交給 DetailViewController 載入，它會丟掉使用者已切走後才回來的過期結果
            pageDetailViewController.loadEpisode(at: index, startPage: startPage)
        }
    }
}

extension ComicEpisodesViewController : UITableViewDataSource , UITableViewDelegate{
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allEpisodes.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116.0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 重用 cell，避免每次捲動都新建並重新發出封面請求
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
        let episode = allEpisodes[indexPath.row]
        cell.textLabel?.text = episode.getName()
        // 封面原圖比列高大，不裁切的話會溢出蓋住下方的分隔線
        cell.clipsToBounds = true
        cell.imageView?.clipsToBounds = true
        cell.imageView?.contentMode = .scaleAspectFit

        // 標示上次看到的那一集，以及下載狀態
        var details = [String]()
        if indexPath.row == lastReadIndex, let entry = lastRead {
            details.append("上次看到第 \(entry.page + 1) 頁")
            cell.detailTextLabel?.textColor = .systemBlue
            cell.accessoryType = .checkmark
        } else {
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.accessoryType = .none
        }
        if let status = downloadStatusText(for: episode) {
            details.append(status)
        }
        cell.detailTextLabel?.text = details.isEmpty ? nil : details.joined(separator: " · ")

        // 重用時先取消舊請求，避免已捲離畫面的下載持續佔用連線
        cell.imageView?.kf.cancelDownloadTask()

        if let urlStr = currentComic.getSmallIconUrl(), let url = URL(string: urlStr) {
            // 8comic 會擋掉沒有 Referer 的請求，缺少這個 modifier 會讓每次重試都必然失敗
            cell.imageView?.kf.setImage(with: url,
                                        placeholder: Self.coverPlaceholder,
                                        // 內建 cell 的 imageView 會跟著圖片尺寸，先降採樣到 coverSize 才會有上下留白
                                        options: [.transition(ImageTransition.fade(1)),
                                                  .processor(DownsamplingImageProcessor(size: Self.coverSize)),
                                                  .scaleFactor(UIScreen.main.scale),
                                                  .requestModifier(refererModifier),
                                                  .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))])
        } else {
            cell.imageView?.image = Self.coverPlaceholder
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // 點上次看的那一集就從上次的頁碼接著看，其他集從第一頁開始
        let page = indexPath.row == lastReadIndex ? (lastRead?.page ?? 0) : 0
        openEpisode(at: indexPath.row, startPage: page)
    }

    /// 往左滑：未下載 → 下載；下載中或排隊中 → 取消；已下載 → 刪除（只有手動刪除）
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let episode = allEpisodes[indexPath.row]
        let comicId = currentComic.getId()
        let action: UIContextualAction
        switch DownloadManager.shared.state(comicId: comicId, episodeUrl: episode.getUrl()) {
        case .none, .incomplete:
            action = UIContextualAction(style: .normal, title: "下載") { _, _, done in
                DownloadManager.shared.download(comic: self.currentComic, episodes: [(episode: episode, order: indexPath.row)])
                done(true)
            }
            action.backgroundColor = .systemBlue
        case .queued, .downloading:
            action = UIContextualAction(style: .normal, title: "取消下載") { _, _, done in
                DownloadManager.shared.deleteEpisode(comicId: comicId, episodeUrl: episode.getUrl())
                done(true)
            }
            action.backgroundColor = .systemOrange
        case .downloaded:
            action = UIContextualAction(style: .destructive, title: "刪除下載") { _, _, done in
                DownloadManager.shared.deleteEpisode(comicId: comicId, episodeUrl: episode.getUrl())
                done(true)
            }
        }
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}
