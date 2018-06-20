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
        WLComics.sharedInstance().loadEpisodeDetail(self.currentEpisode, onLoadDetail: { (episode) in
            episode.setUpPages()
            self.pages = episode.getImageUrlList()
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.detailViewController?.setEpisodeUrl(episode.getUrl())
                self.detailViewController?.updateImages(imgs: self.pages)
            }
        })
        self.tableView.tableHeaderView = nil
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
        let cell:UITableViewCell=UITableViewCell(style: UITableViewCellStyle.subtitle, reuseIdentifier: "Cell");
        cell.textLabel?.text = String("P" + "\(indexPath.row + 1)")
        let url = URL(string:pages[indexPath.row])
        cell.imageView!.kf.setImage(with: url,
                                    placeholder: Image.init(named:"comic_place_holder"),
                                    options: [.transition(ImageTransition.fade(1)),
                                              .requestModifier(WLComics.sharedInstance().buildDownloadEpisodeHeader(currentEpisode.getUrl()))],
                                    progressBlock: { receivedSize, totalSize in
        },
                                    completionHandler: { image, error, cacheType, imageURL in
                                        self.detailViewController?.imgSlider.imageViewArray[indexPath.row].image = image
        })
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        detailViewController?.imgSlider.adjustContentOffsetFor(index: indexPath.row, offsetIndex: indexPath.row, animated: true)
    }
    
    func sliderImageTapped(index: Int) {
        tableView.selectRow(at: IndexPath.init(row: index, section: 0), animated: true, scrollPosition: .none)
    }
    
    func showNextEpisode() {
        if episodeIndex < allEpisodes.count-1 {
            episodeIndex += 1
            self.currentEpisode = self.allEpisodes[episodeIndex]
            detailViewController?.imgSlider.currentIndex = 0
            WLComics.sharedInstance().loadEpisodeDetail(self.currentEpisode, onLoadDetail: { (episode) in
                episode.setUpPages()
                self.pages = episode.getImageUrlList()
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.title = self.currentEpisode.getName()
                    self.detailViewController?.setEpisodeUrl(episode.getUrl())
                    self.detailViewController?.updateImages(imgs: self.pages)
                }
            })
        }
    }
    
}

