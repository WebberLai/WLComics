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
import HUD
import SwiftyDropbox

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
        
        HUD.show(.loading, text: "漫畫載入中...")
       
        DispatchQueue.global(qos: .default).async {
            
            WLComics.sharedInstance().loadAllComics { (comics:[Comic]) in
                self.allComics = comics
            }
            
            if self.currentComic.getId() == "-1" {
                let myAllComics = SwiftyPlistManager.shared.fetchValue(for: "comics", fromPlistWithName: "AllComics") as! [NSMutableDictionary]
                for comic:NSMutableDictionary in myAllComics {
                    let s : String = self.translateChineseStringToPyinyin(chineseStr:comic.object(forKey:"name") as! String)
                    let c = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")
                    c.setId(comic.object(forKey:"comic_id") as! String)
                    c.setSmallIconUrl(comic.object(forKey:"icon_url") as! String)
                    c.setName(comic.object(forKey:"name") as! String)
                    
                    let comicKey = String(s.prefix(1))
                    if var comicValues = self.comicLibrary[comicKey] {
                        comicValues.append(c)
                        self.comicLibrary[comicKey] = comicValues
                    } else {
                        self.comicLibrary[comicKey] = [c]
                    }
                    self.comicSectionTitles = [String](self.comicLibrary.keys)
                    self.comicSectionTitles = self.comicSectionTitles.sorted(by: { $0 < $1 })
                    
                    let sortedByKeyLibrary = self.comicLibrary.sorted { firstDictionary, secondDictionary in
                        return firstDictionary.0 < secondDictionary.0
                    }
                    for (index, title) in self.comicSectionTitles.enumerated(){
                        let comics = sortedByKeyLibrary[index].value
                        let comicDict : NSDictionary = NSDictionary.init(object: comics, forKey: title as NSCopying)
                        self.sortedComicLib.addEntries(from: (comicDict as NSCopying) as! [AnyHashable : Any])
                    }
                }
                DispatchQueue.main.async {
                    HUD.dismiss()
                    self.tableView.reloadData()
                }
            }
        }
    
        self.title = "漫畫列表"
        navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .trash , target: self, action: #selector(clearCache))
        navigationItem.rightBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .search , target: self, action: #selector(startSearch))
    }
    
    func updateAllComicsPlist(){
        let ary  : NSMutableArray = NSMutableArray()

        WLComics.sharedInstance().loadAllComics { (comics:[Comic]) in
            for comic in comics {
                let dict  = NSMutableDictionary.init(object: comic.getName() , forKey: "name" as NSCopying)
                let iconDict = NSDictionary.init(object: comic.getSmallIconUrl() as Any , forKey: "icon_url" as NSCopying)
                let idDict = NSDictionary.init(object: comic.getId() , forKey: "comic_id" as NSCopying)
                dict.addEntries(from: iconDict as! [AnyHashable : Any])
                dict.addEntries(from: idDict as! [AnyHashable : Any])
                
                ary.add(dict)
                
                let s : String = self.translateChineseStringToPyinyin(chineseStr:comic.getName())
                let comicKey = String(s.prefix(1))
                if var comicValues = self.comicLibrary[comicKey] {
                    comicValues.append(comic)
                    self.comicLibrary[comicKey] = comicValues
                } else {
                    self.comicLibrary[comicKey] = [comic]
                }
            }
            
            SwiftyPlistManager.shared.save(ary, forKey:"comics", toPlistWithName: "AllComics", completion: { (error) in
                
            })
            
            self.comicSectionTitles = [String](self.comicLibrary.keys)
            self.comicSectionTitles = self.comicSectionTitles.sorted(by: { $0 < $1 })
            
            let sortedByKeyLibrary = self.comicLibrary.sorted { firstDictionary, secondDictionary in
                return firstDictionary.0 < secondDictionary.0
            }
            for (index, title) in self.comicSectionTitles.enumerated(){
                let comics = sortedByKeyLibrary[index].value
                let comicDict : NSDictionary = NSDictionary.init(object: comics, forKey: title as NSCopying)
                self.sortedComicLib.addEntries(from: (comicDict as NSCopying) as! [AnyHashable : Any])
            }
            DispatchQueue.main.async {
                HUD.dismiss()
                self.tableView.reloadData()
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
        scrollRecordTop = self.tableView.indexPathsForVisibleRows![0]
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
        clearsSelectionOnViewWillAppear = splitViewController!.isCollapsed
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
        if segue.identifier == "showEpisodes" {
            if shouldShowSearchResults {
                currentComic = filterComics [selectIntexPath.row]
            }
            else {
                let comics : [Comic] = self.sortedComicLib.object(forKey:comicSectionTitles[selectIntexPath.section]) as! [Comic]
                let comic = comics[selectIntexPath.row]
                currentComic = comic
            }
            let comicEpisodesViewController = segue.destination as! ComicEpisodesViewController
            comicEpisodesViewController.currentComic = currentComic
            comicEpisodesViewController.title = currentComic.getName()
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
        return comicSectionTitles[section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if shouldShowSearchResults {
            return filterComics.count
        }
        else {
            let comics : [Comic] = self.sortedComicLib.object(forKey:comicSectionTitles[section]) as! [Comic]
            return comics.count
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "ComicTableViewCell") as! ComicTableViewCell
  
        let comics : [Comic] = self.sortedComicLib.object(forKey:comicSectionTitles[indexPath.section]) as! [Comic]
        
        var comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")
        
        if shouldShowSearchResults {
            comic = filterComics [indexPath.row]
        }else {
            comic = comics[indexPath.row]
        }
        
        let comicName = comic.getName()
        
        cell.comicNametextLabel.text = comicName
        
        let url = URL(string:comic.getSmallIconUrl()!)!
        
        cell.coverImageView!.kf.setImage(with: url,
                                    placeholder: Image.init(named:"comic_place_holder"),
                                    options: [.transition(ImageTransition.fade(1))],
                                    progressBlock: { receivedSize, totalSize in
        },
                                    completionHandler: { image, error, cacheType, imageURL in
        })
        
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
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: self.scrollRecordTop, at: .top, animated: false)
        }
    }
    
    //按下搜尋按鈕之後才會顯示搜尋結果
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let searchString = searchController.searchBar.text else {
            return
        }
        if !shouldShowSearchResults {
            shouldShowSearchResults = true
        }
        filterComics = allComics.filter({ (comic) -> Bool in
            let comicName = comic.getName() as NSString
            return (comicName.range(of: searchString, options: NSString.CompareOptions.caseInsensitive).location) != NSNotFound
        })
        self.tableView.reloadData()
        searchController.searchBar.resignFirstResponder()
    }
    
}

