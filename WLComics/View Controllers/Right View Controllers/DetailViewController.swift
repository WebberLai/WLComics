//
//  DetailViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/26.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Swift8ComicSDK

@objc protocol DetailViewControllerDelegate: NSObjectProtocol {
    func sliderImageTapped(index: Int)
    func showNextEpisode()
    func showPreviousEpisode()
}

class DetailViewController: UIViewController,CPSliderDelegate{

    @IBOutlet weak var detailDescriptionLabel: UILabel!
    
    var comicImages = Array<String>()
    
    @IBOutlet weak var imgSlider : CPImageSlider!

    weak var delegate: DetailViewControllerDelegate?
    
    var hidden = false {
        didSet {
            if let nav = navigationController {
                nav.setNavigationBarHidden(hidden, animated: true)
                nav.setToolbarHidden(hidden, animated: true)
            }
        }
    }
    
    // iPhone 用：集數列表和當前 index（用於自動切換上下話）
    var allEpisodes = [Episode]()
    var episodeIndex: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        imgSlider.delegate = self
        imgSlider.enableSwipe = true
        imgSlider.allowCircular = false
        imgSlider.enablePageIndicator = false
        if UIDevice.current.model.description == "iPhone"{
            navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .cancel , target: self, action: #selector(close))
        }
        NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:"BLEClickNotification"),
                                               object:nil, queue:nil,
                                               using:catchNotification(notification:))

        // 滑動超過邊界時自動切換上下話
        imgSlider.onSwipePastLastPage = { [weak self] in
            self?.loadNextEpisode()
        }
        imgSlider.onSwipePastFirstPage = { [weak self] in
            self?.loadPreviousEpisode()
        }
    }

    /// iPhone 模式下載入下一話
    private func loadNextEpisode() {
        // iPad 模式透過 delegate 處理
        if delegate != nil {
            delegate?.showNextEpisode()
            return
        }
        // iPhone 模式自行處理
        guard episodeIndex < allEpisodes.count - 1 else { return }
        episodeIndex += 1
        loadEpisode(at: episodeIndex)
    }

    /// iPhone 模式下載入上一話
    private func loadPreviousEpisode() {
        if delegate != nil {
            delegate?.showPreviousEpisode()
            return
        }
        guard episodeIndex > 0 else { return }
        episodeIndex -= 1
        loadEpisode(at: episodeIndex)
    }

    private func loadEpisode(at index: Int) {
        let episode = allEpisodes[index]
        imgSlider.currentIndex = 0
        self.title = episode.getName()
        WLComics.sharedInstance().loadEpisodeDetail(episode, onLoadDetail: { (episode) in
            episode.setUpPages()
            let pages = episode.getImageUrlList()
            self.setEpisodeUrl(episode.getUrl())
            self.updateImages(imgs: pages)
        })
    }
    
    func catchNotification(notification:Notification) -> Void {
        guard let userInfo = notification.userInfo,
            let action  = userInfo["action"] as? String else {
                print("不支援的鍵盤指令")
                return
        }
        
        if imgSlider.images.count == 0 {
            print("尚未載入漫畫")
            return
        }

        var pageIndex = imgSlider.currentIndex

        if action == UIKeyInputRightArrow {
            pageIndex += 1
            if pageIndex < imgSlider.images.count {
                imgSlider.nextButtonPressed()
            } else if pageIndex == imgSlider.images.count {
                loadNextEpisode()
            }
        } else if action == UIKeyInputLeftArrow {
            pageIndex -= 1
            if pageIndex < 0 {
                pageIndex = 0
                loadPreviousEpisode()
            } else {
                imgSlider.previousButtonPressed()
            }
        }
    }
    
    @objc func close(){
        self.dismiss(animated: true, completion: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.hidesBarsOnTap = true
    }
    
    //設定每集漫畫的root網址
    func setEpisodeUrl(_ url : String){
        self.imgSlider.episodeUrl = url
    }
    
    func updateImages(imgs : Array<String>){
        DispatchQueue.main.async {
            self.imgSlider.images = imgs
        }
    }
    
    func sliderImageTapped(slider: CPImageSlider, index: Int) {
        hidden = !hidden
        self.navigationController?.navigationBar.isHidden = hidden
        delegate?.sliderImageTapped(index: index)
    }
}

