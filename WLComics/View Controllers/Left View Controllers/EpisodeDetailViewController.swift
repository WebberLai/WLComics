//
//  EpisodeDetailViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/28.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Swift8ComicSDK
import Kingfisher
import QuickLook

class EpisodeDetailViewController: UIViewController {
        
    var currentEpisode : Episode!
    
    var allEpisodes = Array<Any>() as! [Episode]
    
    var detailViewController: DetailViewController? = nil
    
    var pages = Array<String>()
    
    var episodeIndex : Int = 0
    
    @IBOutlet weak var tableView : UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
            detailViewController?.imgSlider.currentIndex = 0
            detailViewController?.delegate = self
        }
        self.tableView.tableHeaderView = nil
        loadEpisode(at: episodeIndex)
    }

    /// 縮圖用：降採樣到 cell 大小、低下載優先度，避免搶走右側閱讀器的連線
    private lazy var thumbnailOptions: KingfisherOptionsInfo = [
        .transition(ImageTransition.fade(1)),
        .processor(DownsamplingImageProcessor(size: CGSize(width: 116, height: 116))),
        .scaleFactor(UIScreen.main.scale),
        .cacheOriginalImage,
        .downloadPriority(URLSessionTask.lowPriority),
        // 重試次數壓到 1 次以免搶走閱讀器的連線
        .retryStrategy(DelayRetryStrategy(maxRetryCount: 1, retryInterval: .seconds(2)))
    ]

    /// 載入指定集數並同步更新左側縮圖列表與右側閱讀器
    private func loadEpisode(at index: Int) {
        guard index >= 0 && index < allEpisodes.count else { return }
        episodeIndex = index
        currentEpisode = allEpisodes[index]
        title = currentEpisode.getName()
        WLComics.sharedInstance().loadEpisodeDetail(currentEpisode, onLoadDetail: { [weak self] (episode) in
            episode.setUpPages()
            let pages = episode.getImageUrlList()
            DispatchQueue.main.async {
                // 連續切換集數時，較早發出的請求可能較晚回來，丟掉過期結果；
                // pages 也只在 main queue 寫入，避免和 tableView 讀取產生 data race
                guard let self = self, self.episodeIndex == index else { return }
                self.pages = pages
                self.tableView.reloadData()
                self.detailViewController?.updateEpisode(url: episode.getUrl(), images: pages)
            }
        })
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
        
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}

extension EpisodeDetailViewController : UITableViewDataSource , UITableViewDelegate,DetailViewControllerDelegate{
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return pages.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116.0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 重用 cell，避免每次捲動都新建並重新發出縮圖請求
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")
            ?? UITableViewCell(style: UITableViewCellStyle.subtitle, reuseIdentifier: "Cell")
        cell.textLabel?.text = String("P" + "\(indexPath.row + 1)")

        // 重用時先取消舊請求，避免離開畫面的縮圖持續佔用連線
        cell.imageView?.kf.cancelDownloadTask()

        guard indexPath.row < pages.count else { return cell }
        let url = URL(string:pages[indexPath.row])
        // iPad 上這個清單會與右側閱讀器同時下載，縮圖優先度較低
        cell.imageView?.kf.setImage(with: url,
                                    placeholder: UIImage(named: "comic_place_holder"),
                                    options: thumbnailOptions + [.requestModifier(WLComics.sharedInstance().buildDownloadEpisodeHeader(currentEpisode.getUrl()))])
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        detailViewController?.imgSlider.adjustContentOffsetFor(index: indexPath.row, offsetIndex: indexPath.row, animated: true)
    }
    
    func sliderImageTapped(index: Int) {
        tableView.selectRow(at: IndexPath.init(row: index, section: 0), animated: true, scrollPosition: .none)
    }
    
    func showNextEpisode() {
        guard episodeIndex < allEpisodes.count - 1 else { return }
        loadEpisode(at: episodeIndex + 1)
    }

    func showPreviousEpisode() {
        guard episodeIndex > 0 else { return }
        loadEpisode(at: episodeIndex - 1)
    }
    
}

