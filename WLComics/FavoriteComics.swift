//
//  FavoriteComics.swift
//  WLComics
//
//  Created by Webber Lai on 2017/9/1.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Swift8ComicSDK

class FavoriteComics: NSObject {
    
    static func addComicToMyFavorite(_ comic : Comic){
        var favorites = SwiftyPlistManager.shared.fetchValue(for: "favorite_list", fromPlistWithName: "MyFavoritesComics") as! [NSMutableDictionary]
        let dict  = NSMutableDictionary.init(object: comic.getName() , forKey: "name" as NSCopying)
        let iconDict = NSDictionary.init(object: comic.getSmallIconUrl()! , forKey: "icon_url" as NSCopying)
        let idDict = NSDictionary.init(object: comic.getId() , forKey: "comic_id" as NSCopying)
        dict.addEntries(from: iconDict as! [AnyHashable : Any])
        dict.addEntries(from: idDict as! [AnyHashable : Any])
        favorites.append(dict)
        
        SwiftyPlistManager.shared.save(favorites, forKey: "favorite_list", toPlistWithName: "MyFavoritesComics") { (error) in
            //寫入檔案
        }
    }
    
    static func removeComicFromMyFavorite(_ comic : Comic){
        var favorites = SwiftyPlistManager.shared.fetchValue(for: "favorite_list", fromPlistWithName: "MyFavoritesComics") as! [NSMutableDictionary]
        for (index , c) in favorites.enumerated() {
            if comic.getId() == c.object(forKey: "comic_id") as! String {
                favorites.remove(at: index)
                SwiftyPlistManager.shared.save(favorites, forKey: "favorite_list", toPlistWithName: "MyFavoritesComics") { (error) in
                }
                break
            }
        }
    }
    
    static func listAllFavorite() -> Array<NSMutableDictionary> {
        let favorites = SwiftyPlistManager.shared.fetchValue(for: "favorite_list", fromPlistWithName: "MyFavoritesComics") as! [NSMutableDictionary]
        return favorites
    }
    
    static func checkComicIsMyFavorite(_ comic:Comic) -> Bool{
        var isMyFavorite : Bool = false
        let favorites = SwiftyPlistManager.shared.fetchValue(for: "favorite_list", fromPlistWithName: "MyFavoritesComics") as! [NSMutableDictionary]?
        for (_ , c) in (favorites?.enumerated())!{
            if comic.getId() == (c as AnyObject).object(forKey: "comic_id") as! String {
                isMyFavorite = true
            }
        }
        return isMyFavorite
    }
    
}
