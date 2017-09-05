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

class MasterViewController: UITableViewController , UISearchResultsUpdating,UISearchBarDelegate {
    
    var allComics = [Comic]()
    
    //搜尋過濾之後的找到的漫畫
    var filterComics = [Comic]()
    
    var shouldShowSearchResults = false
    
    var searchController: UISearchController!
    
    var currentComic : Comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")
    
    var selectIndexOfComic : Int = -1
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UINib(nibName: "ComicTableViewCell", bundle: nil), forCellReuseIdentifier: "ComicTableViewCell")

        self.initSearchController()
        
        if currentComic.getId() == "-1" {
            WLComics.sharedInstance().loadAllComics { (comics:[Comic]) in
                self.allComics = comics
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
        self.title = "漫畫列表"
        navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .trash , target: self, action: #selector(clearCache))
    }
    
    func clearCache(){
        ImageCache.default.clearDiskCache()
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

    func insertNewObject(_ sender: Any) {
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.insertRows(at: [indexPath], with: .automatic)
    }

    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showEpisodes" {
            if shouldShowSearchResults {
                currentComic = filterComics [selectIndexOfComic]
            }
            else {
                currentComic = allComics[selectIndexOfComic]
            }
            let comicEpisodesViewController = segue.destination as! ComicEpisodesViewController
            comicEpisodesViewController.currentComic = currentComic
            comicEpisodesViewController.title = currentComic.getName()
        }
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if shouldShowSearchResults {
            return filterComics.count
        }
        else {
            return self.allComics.count
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "ComicTableViewCell") as! ComicTableViewCell

        var comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic("-1", name: "")
        
        if shouldShowSearchResults {
            comic = filterComics [indexPath.row]
        }
        else {
            comic = allComics [indexPath.row]
        }
        
        cell.comicNametextLabel.text = comic.getName()
        
        let url = URL(string:comic.getSmallIconUrl()!)!
        
        cell.coverImageView!.kf.setImage(with: url,
                                    placeholder: Image.init(named:"comic_place_holder"),
                                    options: [.transition(ImageTransition.fade(1))],
                                    progressBlock: { receivedSize, totalSize in
                                        print("\(indexPath.row + 1): \(receivedSize)/\(totalSize)")
        },
                                    completionHandler: { image, error, cacheType, imageURL in
                                        print("\(indexPath.row + 1): Finished")
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
            self.tableView.reloadRows(at: [indexPath], with: .none)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return false
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectIndexOfComic = indexPath.row
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
    }
    
    //按下搜尋按鈕之後才會顯示搜尋結果
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        if !shouldShowSearchResults {
            shouldShowSearchResults = true
            self.tableView.reloadData()
        }
        searchController.searchBar.resignFirstResponder()
    }
    
}

