//
//  ComicEpisodesViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/27.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Swift8ComicSDK
import Kingfisher

class ComicEpisodesViewController: UIViewController {
    
    @IBOutlet weak var tableView : UITableView!
    
    var allEpisodes = Array<Any>() as! [Episode]
    
    var currentComic : Comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")

    var index = 0

    /// 8comic 會擋掉沒有 Referer 的圖片請求，快取一份避免每個 cell 重建
    private let refererModifier = AnyModifier { request in
        var r = request
        r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        return r
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        WLComics.sharedInstance().getR8Comic().loadComicDetail(currentComic) { (comicDetail : Comic) in
            self.allEpisodes = comicDetail.getEpisode()
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
        self.tableView.tableHeaderView = nil
        navigationItem.rightBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .fastForward , target: self, action: #selector(scrollToBottom))
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
            let indexPath = tableView.indexPathForSelectedRow
            let episode = allEpisodes[indexPath!.row]
            let episodeDetailViewController = segue.destination as! EpisodeDetailViewController
            episodeDetailViewController.currentEpisode = episode
            episodeDetailViewController.title = episode.getName()
            episodeDetailViewController.allEpisodes = self.allEpisodes
            episodeDetailViewController.episodeIndex = index
        }else if segue.identifier == "showPageDetail" {
            let navController = segue.destination as! UINavigationController
            let pageDetailViewController = navController.viewControllers[0] as! DetailViewController

            // 傳入所有集數和當前 index，讓 DetailViewController 能自動切換上下話
            pageDetailViewController.allEpisodes = self.allEpisodes
            pageDetailViewController.episodeIndex = index

            let episode = allEpisodes[index]
            pageDetailViewController.title = episode.getName()

            WLComics.sharedInstance().loadEpisodeDetail(episode, onLoadDetail: { (episode) in
                episode.setUpPages()
                let pages = episode.getImageUrlList()
                pageDetailViewController.updateEpisode(url: episode.getUrl(), images: pages)
            })
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
            ?? UITableViewCell(style: UITableViewCellStyle.subtitle, reuseIdentifier: "Cell")
        let episode = allEpisodes[indexPath.row]
        cell.textLabel?.text = episode.getName()

        // 重用時先取消舊請求，避免已捲離畫面的下載持續佔用連線
        cell.imageView?.kf.cancelDownloadTask()

        if let urlStr = currentComic.getSmallIconUrl(), let url = URL(string: urlStr) {
            // 8comic 會擋掉沒有 Referer 的請求，缺少這個 modifier 會讓每次重試都必然失敗
            cell.imageView?.kf.setImage(with: url,
                                        placeholder: UIImage(named: "comic_place_holder"),
                                        options: [.transition(ImageTransition.fade(1)),
                                                  .requestModifier(refererModifier),
                                                  .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))])
        } else {
            cell.imageView?.image = UIImage(named: "comic_place_holder")
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        index = indexPath.row
        if UIDevice.current.model.description == "iPad" {
            self.performSegue(withIdentifier: "showEpisodeDetail", sender: self)
        }
        else if UIDevice.current.model.description == "iPhone"{
            self.performSegue(withIdentifier: "showPageDetail", sender: self)
        }
    }
    
   
}
