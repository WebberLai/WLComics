//
//  FavoriteTableViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/8/31.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Kingfisher
import SwiftyDropbox

class FavoriteTableViewController: UITableViewController {
    
    var myFavoriteList : Array? = FavoriteComics.listAllFavorite()
    
    var currentIndex : Int = 0
    var currentSection : Int = 0
    
    var comicSectionTitles = [String]()
    
    var comicLibrary  : Dictionary = [String: [NSMutableDictionary]]()
    
    var sortedComicLib = NSMutableDictionary()
    
    let client = DropboxClientsManager.authorizedClient
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "收藏列表"
        tableView.register(UINib(nibName: "ComicTableViewCell", bundle: nil), forCellReuseIdentifier: "ComicTableViewCell")
        navigationItem.rightBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .bookmarks , target: self, action: #selector(loginDropbox))
    }
    
    @objc func loginDropbox(){
        DropboxClientsManager.authorizeFromController(UIApplication.shared,
                                                      controller: self,
                                                      openURL: { (url: URL) -> Void in
                                                        UIApplication.shared.openURL(url)
        })
    }
    
    func reloadFavoriteComics () {
        myFavoriteList = FavoriteComics.listAllFavorite()
        self.sortComicList()
        tableView.reloadData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.reloadFavoriteComics()
        //Sync Favorite List
        if let client = DropboxClientsManager.authorizedClient {
            client.files.listFolder(path: "").response { response, error in
                if let result = response {
                    print("Folder contents: \(result)")
                    if result.entries.count == 0 {
                        //上傳本地的
                        print("上傳本地的")
                        self.uploadDropboxPlsit()
                    }else{
                        //同步雲端的下來
                        print("同步雲端的下來")
                        self.downloadDropboxPlist()
                    }
                } else {
                    print("Error: \(error!)")
                }
            }
        }
    }
    
    func uploadDropboxPlsit() {
        if let client = DropboxClientsManager.authorizedClient {
            client.files.listFolder(path: "").response { response, error in
                if let _ = response {
                    let fileData = FavoriteComics.getFavoritePlistData()!
                    //let fileData = "testing data example".data(using: String.Encoding.utf8, allowLossyConversion: false)!
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
    
    func downloadDropboxPlist (){
        if let client = DropboxClientsManager.authorizedClient {
            client.files.listFolder(path:"").response { response, error in
                if let _ = response {
                    let fileManager = FileManager.default
                    let directoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let destURL = directoryURL.appendingPathComponent("MyFavoritesComics.plist")
                    let destination: (URL, HTTPURLResponse) -> URL = { temporaryURL, response in
                        return destURL
                    }
                    client.files.download(path: "/MyFavoritesComics.plist", overwrite: true, destination: destination)
                        .response { response, error in
                            if let response = response {
                                print("Dropbox 下載完成 \(response)")
                                self.reloadFavoriteComics()
                            } else if let error = error {
                                print("Dropbox 下載失敗 \(error)")
                            }
                        }
                        .progress { progressData in
                            print(progressData)
                    }
                } else {
                    print("Dropbox 下載失敗 Error: \(error!)")
                }
            }
        }
    }
    
    func sortComicList(){
        comicLibrary.removeAll()
        sortedComicLib.removeAllObjects()
        for comic : NSMutableDictionary  in myFavoriteList! {
            let s : String = self.translateChineseStringToPyinyin(chineseStr:comic.object(forKey:"name") as! String)
            let comicKey = String(s.prefix(1))
            if var comicValues = self.comicLibrary[comicKey] {
                comicValues.append(comic)
                comicLibrary[comicKey] = comicValues
            } else {
                comicLibrary[comicKey] = [comic]
            }
        }
        
        comicSectionTitles = [String](comicLibrary.keys)
        comicSectionTitles = comicSectionTitles.sorted(by: { $0 < $1 })
        
        let sortedByKeyLibrary = comicLibrary.sorted { firstDictionary, secondDictionary in
            return firstDictionary.0 < secondDictionary.0
        }
        for (index, title) in comicSectionTitles.enumerated(){
            let comics = sortedByKeyLibrary[index].value
            let comicDict : NSDictionary = NSDictionary.init(object: comics, forKey: title as NSCopying)
            sortedComicLib.addEntries(from: (comicDict as NSCopying) as! [AnyHashable : Any])
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
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return comicSectionTitles.count
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
        let comics : [NSMutableDictionary] = self.sortedComicLib.object(forKey:comicSectionTitles[section]) as! [NSMutableDictionary]
        return comics.count
    }

    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ComicTableViewCell") as! ComicTableViewCell
        cell.favoriteBtn.isHidden = true
        let comics : [NSMutableDictionary] = self.sortedComicLib.object(forKey:comicSectionTitles[indexPath.section]) as! [NSMutableDictionary]
        
        let comicDict : NSMutableDictionary = comics[indexPath.row]

        let url = URL(string: comicDict.object(forKey: "icon_url") as! String)!
        
        cell.coverImageView!.kf.setImage(with: url,
                                         placeholder: Image.init(named:"comic_place_holder"),
                                         options: [.transition(ImageTransition.fade(1))],
                                         progressBlock: { receivedSize, totalSize in
        },
                                         completionHandler: { image, error, cacheType, imageURL in
                                            
        })

        cell.comicNametextLabel.text = comicDict.object(forKey: "name") as? String
        return cell
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        currentIndex = indexPath.row
        currentSection = indexPath.section
        self.performSegue(withIdentifier: "showEpisodes", sender: self)
    }

    
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    
    
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            var comics : [NSMutableDictionary] = sortedComicLib.object(forKey:comicSectionTitles[indexPath.section]) as! [NSMutableDictionary]
            let comicDict  : NSMutableDictionary = comics[indexPath.row]
            let deleteComic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(comicDict.object(forKey: "comic_id") as! String ,
                                                                                         name: comicDict.object(forKey: "name") as! String)
            FavoriteComics.removeComicFromMyFavorite(deleteComic)
            
            for (index, element) in (myFavoriteList?.enumerated())!{
                if element == comicDict{
                    myFavoriteList?.remove(at:index)
                    break
                }
            }
            
            for (index,element) in comics.enumerated(){
                if element == comicDict{
                    comics.remove(at:index)
                    break
                }
            }
            sortedComicLib.setObject(comics, forKey: comicSectionTitles[indexPath.section] as NSCopying)
            tableView.deleteRows(at: [indexPath], with: .fade)
            self.uploadDropboxPlsit()
            tableView.reloadData()
        }
    }
    

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showEpisodes" {
            let comics : [NSMutableDictionary] = sortedComicLib.object(forKey:comicSectionTitles[currentSection]) as! [NSMutableDictionary]
            let comicDict  : NSMutableDictionary = comics[currentIndex]
            let currentComic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(comicDict.object(forKey: "comic_id") as! String ,
                                                                                         name: comicDict.object(forKey: "name") as! String)
            currentComic.setSmallIconUrl(comicDict.object(forKey: "icon_url") as! String)
            let comicEpisodesViewController = segue.destination as! ComicEpisodesViewController
            comicEpisodesViewController.currentComic = currentComic
            comicEpisodesViewController.title = currentComic.getName()
        }
    }
    
    
}
