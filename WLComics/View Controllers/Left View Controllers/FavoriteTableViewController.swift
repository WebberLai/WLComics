//
//  FavoriteTableViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/8/31.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Kingfisher

class FavoriteTableViewController: UITableViewController {
    
    var myFavoriteList : Array? = FavoriteComics.listAllFavorite()
    
    var currentIndex : Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "收藏列表"
        tableView.register(UINib(nibName: "ComicTableViewCell", bundle: nil), forCellReuseIdentifier: "ComicTableViewCell")
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        myFavoriteList = FavoriteComics.listAllFavorite()
        tableView.reloadData()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return (myFavoriteList?.count)!
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat{
        return 116
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ComicTableViewCell") as! ComicTableViewCell
        cell.favoriteBtn.isHidden = true
        
        let comicDict : NSMutableDictionary = myFavoriteList?[indexPath.row] as! NSMutableDictionary
        
        cell.comicNametextLabel.text = comicDict.object(forKey: "name") as? String
        
        let url = URL(string: comicDict.object(forKey: "icon_url") as! String)!
        
        cell.coverImageView!.kf.setImage(with: url,
                                         placeholder: Image.init(named:"comic_place_holder"),
                                         options: [.transition(ImageTransition.fade(1))],
                                         progressBlock: { receivedSize, totalSize in
                                            print("\(indexPath.row + 1): \(receivedSize)/\(totalSize)")
                                        },
                                         completionHandler: { image, error, cacheType, imageURL in
                                            print("\(indexPath.row + 1): Finished")
                                        })
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        currentIndex = indexPath.row
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
            let comicDict  : NSMutableDictionary = myFavoriteList![currentIndex]
            let currentComic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(comicDict.object(forKey: "comic_id") as! String , name: comicDict.object(forKey: "name") as! String)
            currentComic.setSmallIconUrl(comicDict.object(forKey: "icon_url") as! String)
            FavoriteComics.removeComicFromMyFavorite(currentComic)
            myFavoriteList?.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
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
            let comicDict  : NSMutableDictionary = myFavoriteList?[currentIndex] as! NSMutableDictionary
            let currentComic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(comicDict.object(forKey: "comic_id") as! String , name: comicDict.object(forKey: "name") as! String)
            currentComic.setSmallIconUrl(comicDict.object(forKey: "icon_url") as! String)
            let comicEpisodesViewController = segue.destination as! ComicEpisodesViewController
            comicEpisodesViewController.currentComic = currentComic
            comicEpisodesViewController.title = currentComic.getName()
        }
    }
    

}
