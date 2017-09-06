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
        let defaults = UserDefaults.standard
        var favorites = defaults.array(forKey: "favorite_list") as! [NSMutableDictionary]?
        if favorites == nil {
            let favoriteList = NSMutableArray.init() as! [NSMutableDictionary]
            defaults.set(favoriteList, forKey: "favorite_list")
            defaults.synchronize()
        }
        let dict  = NSMutableDictionary.init(object: comic.getName() , forKey: "name" as NSCopying)
        let iconDict = NSDictionary.init(object: comic.getSmallIconUrl()! , forKey: "icon_url" as NSCopying)
        let idDict = NSDictionary.init(object: comic.getId() , forKey: "comic_id" as NSCopying)
        dict.addEntries(from: iconDict as! [AnyHashable : Any])
        dict.addEntries(from: idDict as! [AnyHashable : Any])
        favorites?.append(dict)
        defaults.set(favorites, forKey: "favorite_list")
        defaults.synchronize()
    }
    
    static func removeComicFromMyFavorite(_ comic : Comic){
        let defaults = UserDefaults.standard
        var favorites = defaults.array(forKey: "favorite_list") as! [NSMutableDictionary]?
        for (index , c) in (favorites?.enumerated())!{
            if comic.getId() == c.object(forKey: "comic_id") as! String {
                favorites?.remove(at: index)
                break
            }
        }
        defaults.set(favorites, forKey: "favorite_list")
        defaults.synchronize()
    }
    
    static func listAllFavorite() -> NSMutableArray {
        let defaults = UserDefaults.standard
        var favorites : [NSMutableDictionary]? = defaults.array(forKey: "favorite_list") as! [NSMutableDictionary]?
        if favorites == nil {
            let favoriteList = NSMutableArray.init()
            favorites = favoriteList as? [NSMutableDictionary]
            defaults.set(favoriteList, forKey: "favorite_list")
            defaults.synchronize()
        }
        return favorites as! NSMutableArray
    }
    
    static func checkComicIsMyFavorite(_ comic:Comic) -> Bool{
        var isMyFavorite : Bool = false
        let defaults = UserDefaults.standard
        let favorites : [NSMutableDictionary]? = defaults.array(forKey: "favorite_list") as! [NSMutableDictionary]?
        for (_ , c) in (favorites?.enumerated())!{
            if comic.getId() == (c as AnyObject).object(forKey: "comic_id") as! String {
                isMyFavorite = true
            }
        }
        return isMyFavorite
    }
    
}
