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

    override func viewDidLoad() {
        super.viewDidLoad()
        WLComics.sharedInstance().getR8Comic().loadComicDetail(currentComic) { (comicDetail : Comic) in
            self.allEpisodes = comicDetail.getEpisode()
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
        self.tableView.tableHeaderView = nil
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
        }else if segue.identifier == "showPageDetail" {
            let navController = segue.destination as! UINavigationController
            let pageDetailViewController = navController.viewControllers[0] as! DetailViewController
            
            let episode = allEpisodes[index]
            pageDetailViewController.title = episode.getName()
            
            WLComics.sharedInstance().loadEpisodeDetail(episode, onLoadDetail: { (episode) in
                episode.setUpPages()
                let pages = episode.getImageUrlList()
                pageDetailViewController.setEpisodeUrl(episode.getUrl())
                pageDetailViewController.updateImages(imgs: pages)
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
        return 100.0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell:UITableViewCell=UITableViewCell(style: UITableViewCellStyle.subtitle, reuseIdentifier: "Cell");
        let episode = allEpisodes[indexPath.row]
        cell.textLabel?.text = episode.getName()
        let url = URL(string:currentComic.getSmallIconUrl()!)!
        cell.imageView!.kf.setImage(with: url,
                                    placeholder: Image.init(named:"comic_place_holder"),
                                    options: [.transition(ImageTransition.fade(1))],
                                    progressBlock: { receivedSize, totalSize in
                                        print("\(indexPath.row + 1): \(receivedSize)/\(totalSize)")
        },
                                    completionHandler: { image, error, cacheType, imageURL in
                                        print("\(indexPath.row + 1): Finished")
        })
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print(UIDevice.current.model)
        index = indexPath.row
        if UIDevice.current.model.description == "iPad" {
            self.performSegue(withIdentifier: "showEpisodeDetail", sender: self)
        }
        else if UIDevice.current.model.description == "iPhone"{
            self.performSegue(withIdentifier: "showPageDetail", sender: self)
        }
    }
    
   
}
