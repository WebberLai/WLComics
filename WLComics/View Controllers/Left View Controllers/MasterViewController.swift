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

class MasterViewController: UITableViewController , UISearchResultsUpdating,UISearchBarDelegate {
    
    var allComics = [Comic]()
    
    //搜尋過濾之後的找到的漫畫
    var filterComics = [Comic]()
    
    var shouldShowSearchResults = false
    
    var searchController: UISearchController!
    
    var currentComic : Comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")
    
    var scrollRecordTop :  IndexPath = IndexPath.init(row: 0, section: 0)
    
    var comicLibrary  : Dictionary = [String: [Comic]]()
    
    var comicSectionTitles = [String]()
    
    var sortedComicLib = NSMutableDictionary()
    
    var selectIntexPath  : IndexPath = IndexPath()
    
    let client = DropboxClientsManager.authorizedClient
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UINib(nibName: "ComicTableViewCell", bundle: nil), forCellReuseIdentifier: "ComicTableViewCell")

        self.initSearchController()
        
        SVProgressHUD.show(withStatus: "漫畫載入中...")

        WLComics.sharedInstance().loadAllComics { (comics:[Comic]) in
            DispatchQueue.main.async {
                self.allComics = comics
                self.buildComicLibrary(from: comics)
                SVProgressHUD.dismiss()
                self.tableView.reloadData()
            }
        }
    
        self.title = "漫畫列表"
        navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .trash , target: self, action: #selector(clearCache))
        navigationItem.rightBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .search , target: self, action: #selector(startSearch))
    }
    
    func buildComicLibrary(from comics: [Comic]) {
        comicLibrary.removeAll()
        sortedComicLib.removeAllObjects()

        for comic in comics {
            let s = translateChineseStringToPyinyin(chineseStr: comic.getName())
            let comicKey = String(s.prefix(1))
            if var comicValues = comicLibrary[comicKey] {
                comicValues.append(comic)
                comicLibrary[comicKey] = comicValues
            } else {
                comicLibrary[comicKey] = [comic]
            }
        }

        comicSectionTitles = comicLibrary.keys.sorted()

        for title in comicSectionTitles {
            if let comicsInSection = comicLibrary[title] {
                sortedComicLib.setObject(comicsInSection, forKey: title as NSCopying)
            }
        }
    }

    func translateChineseStringToPyinyin(chineseStr:String) -> String {
        var translatedPinyinStr:String = ""
        let zhcnStrToTranslate:CFMutableString = NSMutableString(string: chineseStr)
        var translatedOk:Bool = CFStringTransform(zhcnStrToTranslate, nil, kCFStringTransformMandarinLatin, false)
        if translatedOk {
            let translatedPinyinWithAccents = zhcnStrToTranslate
            translatedOk = CFStringTransform(translatedPinyinWithAccents, nil, kCFStringTransformStripCombiningMarks, false)
            if translatedOk {
                translatedPinyinStr = translatedPinyinWithAccents as String
            }
        }
        return translatedPinyinStr.uppercased()
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
                      let comics = self.sortedComicLib.object(forKey:comicSectionTitles[selectIntexPath.section]) as? [Comic],
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
                  let comics = self.sortedComicLib.object(forKey:comicSectionTitles[section]) as? [Comic] else { return 0 }
            return comics.count
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "ComicTableViewCell") as! ComicTableViewCell
  
        let comics = (indexPath.section < comicSectionTitles.count) ?
            self.sortedComicLib.object(forKey:comicSectionTitles[indexPath.section]) as? [Comic] ?? [] : []

        var comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")

        if shouldShowSearchResults {
            guard indexPath.row < filterComics.count else { return cell }
            comic = filterComics[indexPath.row]
        } else {
            guard indexPath.row < comics.count else { return cell }
            comic = comics[indexPath.row]
        }
        
        let comicName = comic.getName()
        
        cell.comicNametextLabel.text = comicName
        
        let modifier = AnyModifier { request in
            var r = request
            r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
            return r
        }
        if let urlStr = comic.getSmallIconUrl(), let url = URL(string: urlStr) {
            cell.coverImageView?.kf.setImage(with: url,
                                        placeholder: UIImage(named: "comic_place_holder"),
                                        options: [.transition(ImageTransition.fade(1)),
                                                  .requestModifier(modifier)])
        } else {
            cell.coverImageView?.image = UIImage(named: "comic_place_holder")
        }
        
        let isFavorite : Bool = FavoriteComics.checkComicIsMyFavorite(comic)
        if isFavorite == false {
            cell.favoriteBtn.setImage(UIImage.init(named: "dislike"), for: .normal)
        }else {
            cell.favoriteBtn.setImage(UIImage.init(named: "like"), for: .normal)
        }
        
        cell.favoriteButtonPress = { (button) in
            if isFavorite == false {
               FavoriteComics.addComicToMyFavorite(comic)
            }else {
                FavoriteComics.removeComicFromMyFavorite(comic)
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
                  let comics = self.sortedComicLib.object(forKey: self.comicSectionTitles[self.scrollRecordTop.section]) as? [Comic],
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

