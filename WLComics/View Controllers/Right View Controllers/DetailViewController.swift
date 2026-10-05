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
    /// iPhone 用：目前漫畫的 id，記錄閱讀進度用（iPad 由 EpisodeDetailViewController 透過 updateEpisode 傳入）
    var comicId: String?

    /// 目前畫面上這一集所屬的漫畫與集數，跟著 updateEpisode 一起更新，
    /// 避免切換漫畫時新舊資料交錯而把進度記到別部漫畫
    private var displayedComicId: String?
    private var displayedEpisodeUrl: String?
    private var displayedEpisodeName = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        imgSlider.delegate = self
        imgSlider.enableSwipe = true
        imgSlider.allowCircular = false
        imgSlider.enablePageIndicator = false
        // 跟著系統深淺色；storyboard 裡寫死白底，深色模式下會和左側列表黑白交錯
        view.backgroundColor = .systemBackground
        imgSlider.backgroundColor = .systemBackground
        if UIDevice.current.model.description == "iPhone"{
            navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .cancel , target: self, action: #selector(close))
        }
        // 用 selector 版本：不會強引用 self，VC 釋放時系統自動移除，
        // 避免關掉閱讀器後舊的 VC 還在背景回應方向鍵
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(catchNotification(notification:)),
                                               name: Notification.Name(rawValue:"BLEClickNotification"),
                                               object: nil)

        // 滑動超過邊界時自動切換上下話
        imgSlider.onSwipePastLastPage = { [weak self] in
            self?.loadNextEpisode()
        }
        imgSlider.onSwipePastFirstPage = { [weak self] in
            self?.loadPreviousEpisode()
        }
        // 每翻到新的一頁就記錄閱讀進度
        imgSlider.onPageChanged = { [weak self] page in
            guard let self = self,
                  let comicId = self.displayedComicId,
                  let url = self.displayedEpisodeUrl else { return }
            ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: self.displayedEpisodeName, page: page)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Mac 上視窗為橫向時改用雙頁閱讀；iPad / iPhone 維持單頁
        let isLandscape = imgSlider.bounds.width > imgSlider.bounds.height
        imgSlider.isSpreadMode = ProcessInfo.processInfo.isiOSAppOnMac && isLandscape
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
        loadEpisode(at: episodeIndex + 1)
    }

    /// iPhone 模式下載入上一話
    private func loadPreviousEpisode() {
        if delegate != nil {
            delegate?.showPreviousEpisode()
            return
        }
        guard episodeIndex > 0 else { return }
        loadEpisode(at: episodeIndex - 1)
    }

    /// 載入指定集數。可在 view 載入前呼叫（例如 prepare(for:segue:)），畫面更新一律在 main queue
    func loadEpisode(at index: Int, startPage: Int = 0) {
        guard index >= 0 && index < allEpisodes.count else { return }
        episodeIndex = index
        let episode = allEpisodes[index]
        let comicId = self.comicId
        self.title = episode.getName()
        WLComics.sharedInstance().loadEpisodeDetail(episode, onLoadDetail: { [weak self] (episode) in
            episode.setUpPages()
            let pages = episode.getImageUrlList()
            DispatchQueue.main.async {
                // 連續切換集數時，較早發出的請求可能較晚回來，丟掉過期結果
                guard let self = self, self.episodeIndex == index else { return }
                self.updateEpisode(url: episode.getUrl(), images: pages, name: episode.getName(),
                                   comicId: comicId, startPage: startPage)
            }
        })
    }

    @objc func catchNotification(notification:Notification) -> Void {
        guard let userInfo = notification.userInfo,
            let action  = userInfo["action"] as? String else {
                print("不支援的鍵盤指令")
                return
        }
        
        if imgSlider.images.count == 0 {
            print("尚未載入漫畫")
            return
        }

        // 翻到最後／第一頁時，slider 會透過 onSwipePastLastPage / onSwipePastFirstPage 換話，
        // 雙頁模式下也會自動一次翻兩頁
        if action == UIKeyInputRightArrow {
            imgSlider.nextButtonPressed()
        } else if action == UIKeyInputLeftArrow {
            imgSlider.previousButtonPressed()
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

    /// 確保 episodeUrl 和 images 在同一個 main queue 週期設定，避免 race condition
    /// startPage：從第幾頁開始（繼續閱讀用），超出範圍會自動夾限
    func updateEpisode(url: String, images: [String], name: String = "", comicId: String? = nil, startPage: Int = 0) {
        DispatchQueue.main.async {
            self.imgSlider.cancelAllDownloads()
            // 要在設定 images 之前更新，images 一設定就會回報頁碼
            self.displayedComicId = comicId
            self.displayedEpisodeUrl = url
            self.displayedEpisodeName = name
            self.imgSlider.currentIndex = min(max(startPage, 0), max(images.count - 1, 0))
            self.imgSlider.episodeUrl = url
            self.imgSlider.images = images
        }
    }
    
    func sliderImageTapped(slider: CPImageSlider, index: Int) {
        hidden = !hidden
        self.navigationController?.navigationBar.isHidden = hidden
        delegate?.sliderImageTapped(index: index)
    }
}

