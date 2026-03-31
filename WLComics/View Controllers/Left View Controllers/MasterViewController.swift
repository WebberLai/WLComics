//
//  MasterViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/26.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Swift8ComicSDK
import Kingfisher
import SwiftyDropbox
import SVProgressHUD

class MasterViewController: UITableViewController , UISearchResultsUpdating,UISearchBarDelegate, UITableViewDataSourcePrefetching {

    var allComics = [Comic]()

    //搜尋過濾之後的找到的漫畫
    var filterComics = [Comic]()

    var shouldShowSearchResults = false

    var searchController: UISearchController!

    var currentComic : Comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")

    var scrollRecordTop :  IndexPath = IndexPath.init(row: 0, section: 0)

    // 改用 Swift Dictionary 取代 NSMutableDictionary，避免型別轉換開銷
    var sortedComicLib = [String: [Comic]]()

    var comicSectionTitles = [String]()

    var selectIntexPath  : IndexPath = IndexPath()

    let client = DropboxClientsManager.authorizedClient

    // 快取 placeholder 圖片和 Kingfisher modifier，避免每個 cell 重複建立
    private lazy var placeholderImage = UIImage(named: "comic_place_holder")
    private let refererModifier = AnyModifier { request in
        var r = request
        r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        return r
    }

    // 快取收藏狀態，避免每個 cell 都讀 plist
    private var favoriteIds = Set<String>()

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UINib(nibName: "ComicTableViewCell", bundle: nil), forCellReuseIdentifier: "ComicTableViewCell")
        tableView.prefetchDataSource = self

        self.initSearchController()

        SVProgressHUD.show(withStatus: "漫畫載入中...")

        // 在背景執行拼音排序（10000+ 筆的 CFStringTransform 很慢）
        WLComics.sharedInstance().loadAllComics { (comics:[Comic]) in
            DispatchQueue.global(qos: .userInitiated).async {
                let library = self.buildComicLibrary(from: comics)
                DispatchQueue.main.async {
                    self.allComics = comics
                    self.sortedComicLib = library.sorted
                    self.comicSectionTitles = library.titles
                    self.reloadFavoriteIds()
                    SVProgressHUD.dismiss()
                    self.tableView.reloadData()
                }
            }
        }

        self.title = "漫畫列表"
        navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .trash , target: self, action: #selector(clearCache))
        navigationItem.rightBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .search , target: self, action: #selector(startSearch))
    }

    func reloadFavoriteIds() {
        favoriteIds = Set(FavoriteComics.listAllFavorite().compactMap { $0.object(forKey: "comic_id") as? String })
    }

    func buildComicLibrary(from comics: [Comic]) -> (sorted: [String: [Comic]], titles: [String]) {
        var library = [String: [Comic]]()

        for comic in comics {
            let s = translateChineseStringToPyinyin(chineseStr: comic.getName())
            let comicKey = String(s.prefix(1))
            library[comicKey, default: []].append(comic)
        }

        let titles = library.keys.sorted()
        return (sorted: library, titles: titles)
    }

    func translateChineseStringToPyinyin(chineseStr:String) -> String {
        let zhcnStrToTranslate:CFMutableString = NSMutableString(string: chineseStr)
        if CFStringTransform(zhcnStrToTranslate, nil, kCFStringTransformMandarinLatin, false) {
            if CFStringTransform(zhcnStrToTranslate, nil, kCFStringTransformStripCombiningMarks, false) {
                return (zhcnStrToTranslate as String).uppercased()
            }
        }
        return chineseStr.uppercased()
    }
    
    
    @objc func clearCache(){
        let alert = UIAlertController(title: "清除暫存資料" , message: "確定要清除暫存資料?" , preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "是", style: .default, handler: { (_) in
            ImageCache.default.clearDiskCache()
        }))
        alert.addAction(UIAlertAction(title: "否", style: .default, handler: { (_) in
            
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func startSearch() {
        searchController.searchBar.becomeFirstResponder()
        if let visibleRows = self.tableView.indexPathsForVisibleRows, !visibleRows.isEmpty {
            scrollRecordTop = visibleRows[0]
        }
    }
    
    func initSearchController() {
        self.definesPresentationContext = true
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.dimsBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "輸入想要搜尋的漫畫名稱"
        searchController.searchBar.delegate = self
        //把搜尋功能加入tableview的最上面
        self.tableView.tableHeaderView = searchController.searchBar
    }

    override func viewWillAppear(_ animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController?.isCollapsed ?? true
        super.viewWillAppear(animated)
        // 重新載入收藏狀態（從其他頁面返回時可能已變更）
        reloadFavoriteIds()
        self.tableView.reloadData()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        shouldShowSearchResults = false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func uploadDropboxPlsit() {
        if let client = DropboxClientsManager.authorizedClient {
            client.files.listFolder(path: "").response { response, error in
                if let _ = response {
                    let fileData = FavoriteComics.getFavoritePlistData()!
                    let _ = client.files.upload(path: "/MyFavoritesComics.plist", mode: .overwrite , input: fileData).response { response, error in
                        if let response = response {
                            print("Dropbox 上傳完成 \(response)")
                        } else if let error = error {
                            print("Dropbox 上傳失敗 \(error)")
                        }
                        }
                        .progress { progressData in
                            print(progressData)
                    }
                } else {
                    print("Dropbox 上傳失敗 Error: \(error!)")
                }
            }
        }
    }
    
    func insertNewObject(_ sender: Any) {
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.insertRows(at: [indexPath], with: .automatic)
    }

    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        print("[DEBUG] prepare segue=\(segue.identifier ?? "nil"), selectIntexPath=\(selectIntexPath)")
        if segue.identifier == "showEpisodes" {
            if shouldShowSearchResults {
                print("[DEBUG] search mode: row=\(selectIntexPath.row), filterComics.count=\(filterComics.count)")
                guard selectIntexPath.row < filterComics.count else { return }
                currentComic = filterComics[selectIntexPath.row]
            }
            else {
                print("[DEBUG] normal mode: section=\(selectIntexPath.section), comicSectionTitles.count=\(comicSectionTitles.count)")
                guard selectIntexPath.section < comicSectionTitles.count,
                      let comics = self.sortedComicLib[comicSectionTitles[selectIntexPath.section]],
                      selectIntexPath.row < comics.count else { return }
                print("[DEBUG] comics.count=\(comics.count), row=\(selectIntexPath.row)")
                currentComic = comics[selectIntexPath.row]
            }
            let comicEpisodesViewController = segue.destination as! ComicEpisodesViewController
            comicEpisodesViewController.currentComic = currentComic
            comicEpisodesViewController.title = currentComic.getName()
            print("[DEBUG] navigate to episodes: \(currentComic.getName())")
        }
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        if shouldShowSearchResults {
            return 1
        }else {
            return comicSectionTitles.count
        }
    }
    
    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        var tpIndex:Int = 0
        for character in comicSectionTitles{
            if character == title{
                return tpIndex
            }
            tpIndex += 1
        }
        return 0
    }
    
    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return comicSectionTitles
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < comicSectionTitles.count else { return nil }
        return comicSectionTitles[section]
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.contentView.backgroundColor = UIColor.white
        header.textLabel?.textColor = UIColor.darkGray
        header.textLabel?.font = UIFont.boldSystemFont(ofSize: 15)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if shouldShowSearchResults {
            return filterComics.count
        }
        else {
            guard section < comicSectionTitles.count,
                  let comics = self.sortedComicLib[comicSectionTitles[section]] else { return 0 }
            return comics.count
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "ComicTableViewCell") as! ComicTableViewCell

        let comic: Comic
        if shouldShowSearchResults {
            guard indexPath.row < filterComics.count else { return cell }
            comic = filterComics[indexPath.row]
        } else {
            guard indexPath.section < comicSectionTitles.count,
                  let comics = sortedComicLib[comicSectionTitles[indexPath.section]],
                  indexPath.row < comics.count else { return cell }
            comic = comics[indexPath.row]
        }

        cell.comicNametextLabel.text = comic.getName()

        // 使用快取的 modifier 和 placeholder，不再每次建立新物件
        if let urlStr = comic.getSmallIconUrl(), let url = URL(string: urlStr) {
            cell.coverImageView?.kf.setImage(with: url,
                                        placeholder: placeholderImage,
                                        options: [.transition(ImageTransition.fade(1)),
                                                  .requestModifier(refererModifier)])
        } else {
            cell.coverImageView?.image = placeholderImage
        }

        // 用記憶體中的 Set 查詢收藏狀態，不再每個 cell 都讀 plist
        let isFavorite = favoriteIds.contains(comic.getId())
        cell.favoriteBtn.setImage(UIImage(named: isFavorite ? "like" : "dislike"), for: .normal)

        cell.favoriteButtonPress = { [weak self] (button) in
            guard let self = self else { return }
            if isFavorite {
                FavoriteComics.removeComicFromMyFavorite(comic)
                self.favoriteIds.remove(comic.getId())
            } else {
                FavoriteComics.addComicToMyFavorite(comic)
                self.favoriteIds.insert(comic.getId())
            }
            self.uploadDropboxPlsit()
            self.tableView.reloadRows(at: [indexPath], with: .none)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return false
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectIntexPath = indexPath
        self.performSegue(withIdentifier: "showEpisodes", sender: self)
    }

    // MARK: - Prefetch（預先載入即將出現的封面圖片）

    private func comicForIndexPath(_ indexPath: IndexPath) -> Comic? {
        if shouldShowSearchResults {
            guard indexPath.row < filterComics.count else { return nil }
            return filterComics[indexPath.row]
        } else {
            guard indexPath.section < comicSectionTitles.count,
                  let comics = sortedComicLib[comicSectionTitles[indexPath.section]],
                  indexPath.row < comics.count else { return nil }
            return comics[indexPath.row]
        }
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap { comicForIndexPath($0) }
            .compactMap { $0.getSmallIconUrl() }
            .compactMap { URL(string: $0) }
        ImagePrefetcher(urls: urls, options: [.requestModifier(refererModifier)]).start()
    }

    // MARK: - Search Bar
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchString = searchController.searchBar.text else {
            return
        }
        filterComics = allComics.filter({ (comic) -> Bool in
            let comicName = comic.getName() as NSString
            return (comicName.range(of: searchString, options: NSString.CompareOptions.caseInsensitive).location) != NSNotFound
        })
        
        self.tableView.reloadData()
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        shouldShowSearchResults = true
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        shouldShowSearchResults = false
        self.tableView.reloadData()
        DispatchQueue.main.async {
            guard self.scrollRecordTop.section < self.comicSectionTitles.count,
                  let comics = self.sortedComicLib[self.comicSectionTitles[self.scrollRecordTop.section]],
                  self.scrollRecordTop.row < comics.count else { return }
            self.tableView.scrollToRow(at: self.scrollRecordTop, at: .top, animated: false)
        }
    }
    
    //按下搜尋按鈕之後，先顯示本地結果，再呼叫搜尋 API 補充
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let searchString = searchController.searchBar.text, !searchString.isEmpty else {
            return
        }
        if !shouldShowSearchResults {
            shouldShowSearchResults = true
        }

        // 先顯示本地過濾結果
        filterComics = allComics.filter({ (comic) -> Bool in
            let comicName = comic.getName() as NSString
            return (comicName.range(of: searchString, options: NSString.CompareOptions.caseInsensitive).location) != NSNotFound
        })
        self.tableView.reloadData()
        searchController.searchBar.resignFirstResponder()

        // 呼叫搜尋 API 找更多結果
        WLComics.sharedInstance().searchComics(keyword: searchString) { (comics:[Comic]) in
            DispatchQueue.main.async {
                // 合併 API 結果（排除已有的）
                let existingIds = Set(self.filterComics.map { $0.getId() })
                let newComics = comics.filter { !existingIds.contains($0.getId()) }
                if !newComics.isEmpty {
                    self.filterComics.append(contentsOf: newComics)
                    // 同時更新 allComics 以供後續本地搜尋
                    let allIds = Set(self.allComics.map { $0.getId() })
                    for comic in newComics {
                        if !allIds.contains(comic.getId()) {
                            self.allComics.append(comic)
                        }
                    }
                    self.tableView.reloadData()
                }
            }
        }
    }
    
}

