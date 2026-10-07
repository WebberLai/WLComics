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
    /// 目前這一集的頁面網址，切換閱讀模式時交給另一個閱讀器
    private var displayedImages = [String]()

    /// 上下捲動閱讀器（條漫用），疊在 imgSlider 上方，依模式切換顯示
    private let verticalReader = VerticalReaderView()
    private var currentMode: ReadingMode = .horizontal
    private lazy var modeButton = UIBarButtonItem(image: nil, style: .plain, target: self, action: #selector(toggleReadingMode))

    /// 目前顯示中的閱讀器所在的頁碼
    private var currentPage: Int {
        return currentMode == .horizontal ? imgSlider.currentIndex : verticalReader.currentIndex
    }

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
            self?.saveProgress(page: page)
        }
        setUpVerticalReader()
    }

    private func setUpVerticalReader() {
        verticalReader.isHidden = true
        verticalReader.backgroundColor = .systemBackground
        verticalReader.translatesAutoresizingMaskIntoConstraints = false
        let container: UIView = imgSlider.superview ?? view
        container.insertSubview(verticalReader, aboveSubview: imgSlider)
        NSLayoutConstraint.activate([
            verticalReader.topAnchor.constraint(equalTo: imgSlider.topAnchor),
            verticalReader.bottomAnchor.constraint(equalTo: imgSlider.bottomAnchor),
            verticalReader.leadingAnchor.constraint(equalTo: imgSlider.leadingAnchor),
            verticalReader.trailingAnchor.constraint(equalTo: imgSlider.trailingAnchor),
        ])
        verticalReader.onSwipePastLastPage = { [weak self] in
            self?.loadNextEpisode()
        }
        verticalReader.onSwipePastFirstPage = { [weak self] in
            self?.loadPreviousEpisode()
        }
        verticalReader.onPageChanged = { [weak self] page in
            self?.saveProgress(page: page)
        }
        verticalReader.onTap = { [weak self] in
            guard let self = self else { return }
            self.readerTapped(index: self.verticalReader.currentIndex)
        }
        updateModeButton()
    }

    private func saveProgress(page: Int) {
        guard let comicId = displayedComicId, let url = displayedEpisodeUrl else { return }
        ReadingProgress.save(comicId: comicId, episodeUrl: url, episodeName: displayedEpisodeName, page: page)
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
        // 已下載的集數直接讀本機檔案，不需要連網
        if let comicId = comicId,
           let localPages = DownloadManager.shared.localPageURLs(comicId: comicId, episodeUrl: episode.getUrl()) {
            updateEpisode(url: episode.getUrl(), images: localPages.map { $0.absoluteString }, name: episode.getName(),
                          comicId: comicId, startPage: startPage)
            return
        }
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
        
        if displayedImages.isEmpty {
            print("尚未載入漫畫")
            return
        }

        // 翻到最後／第一頁時，閱讀器會透過 onSwipePastLastPage / onSwipePastFirstPage 換話，
        // 雙頁模式下也會自動一次翻兩頁；上下捲動模式則是捲動約一個畫面
        let isNext = action == UIKeyCommand.inputRightArrow
        guard isNext || action == UIKeyCommand.inputLeftArrow else { return }
        switch currentMode {
        case .horizontal:
            isNext ? imgSlider.nextButtonPressed() : imgSlider.previousButtonPressed()
        case .vertical:
            isNext ? verticalReader.nextButtonPressed() : verticalReader.previousButtonPressed()
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
        updateBarsOnTap()
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
            // 要在設定 images 之前更新，images 一設定就會回報頁碼
            self.displayedComicId = comicId
            self.displayedEpisodeUrl = url
            self.displayedEpisodeName = name
            self.displayedImages = images
            // 沒有手動選過的漫畫一律用左右翻頁
            let savedMode = comicId.flatMap { ReadingModeStore.mode(for: $0) }
            self.show(mode: savedMode ?? .horizontal, page: startPage)
        }
    }

    /// 顯示指定模式的閱讀器，並把目前這一集交給它、停在 page；另一個閱讀器清空並取消下載
    private func show(mode: ReadingMode, page: Int) {
        currentMode = mode
        imgSlider.cancelAllDownloads()
        verticalReader.cancelAllDownloads()
        let images = displayedImages
        let target = min(max(page, 0), max(images.count - 1, 0))
        switch mode {
        case .horizontal:
            verticalReader.images = []
            verticalReader.isHidden = true
            imgSlider.isHidden = false
            imgSlider.currentIndex = target
            imgSlider.episodeUrl = displayedEpisodeUrl
            imgSlider.images = images
        case .vertical:
            imgSlider.images = []
            imgSlider.isHidden = true
            verticalReader.isHidden = false
            verticalReader.currentIndex = target
            verticalReader.episodeUrl = displayedEpisodeUrl
            verticalReader.images = images
        }
        updateModeButton()
        updateBarsOnTap()
    }

    /// 上下捲動模式自己處理點擊（要等雙擊判定），關掉導覽列的點擊隱藏，避免雙擊縮放時導覽列也跟著切換
    private func updateBarsOnTap() {
        navigationController?.hidesBarsOnTap = currentMode == .horizontal
    }

    /// 導覽列按鈕：手動切換閱讀模式並記住，停在同一頁
    @objc private func toggleReadingMode() {
        guard let comicId = displayedComicId else { return }
        let newMode: ReadingMode = currentMode == .horizontal ? .vertical : .horizontal
        ReadingModeStore.setManual(newMode, for: comicId)
        show(mode: newMode, page: currentPage)
    }

    private func updateModeButton() {
        // 圖示表示「按下後會切換成的方向」
        modeButton.image = UIImage(systemName: currentMode == .horizontal ? "arrow.up.and.down" : "arrow.left.and.right")
        navigationItem.rightBarButtonItem = displayedComicId == nil ? nil : modeButton
    }

    /// iPad 左側縮圖：捲到指定頁
    func scrollToPage(_ page: Int) {
        switch currentMode {
        case .horizontal:
            imgSlider.scrollToPage(page)
        case .vertical:
            verticalReader.scrollToPage(page)
        }
    }
    
    func sliderImageTapped(slider: CPImageSlider, index: Int) {
        readerTapped(index: index)
    }

    /// 點擊閱讀器：切換導覽列顯示，並同步 iPad 左側縮圖的選取
    private func readerTapped(index: Int) {
        hidden = !hidden
        self.navigationController?.navigationBar.isHidden = hidden
        delegate?.sliderImageTapped(index: index)
    }
}

