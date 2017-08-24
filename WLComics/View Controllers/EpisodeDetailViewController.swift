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
    
    var detailViewController: DetailViewController? = nil
    
    var pages = Array<String>()
    
    @IBOutlet weak var tableView : UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
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
        
        // Do any additional setup after loading the view.
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

extension EpisodeDetailViewController : UITableViewDataSource , UITableViewDelegate{
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return pages.count
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
                                        print("\(indexPath.row + 1): \(receivedSize)/\(totalSize)")
        },
                                    completionHandler: { image, error, cacheType, imageURL in
                                        print("\(indexPath.row + 1): Finished")
        })
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
}

