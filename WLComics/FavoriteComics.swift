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
        let favorites = (defaults.object(forKey: "favorite_list") as! NSMutableArray).mutableCopy() as! NSMutableArray
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
        favorites.add(dict)
        defaults.set(favorites, forKey: "favorite_list")
        defaults.synchronize()
    }
    
    static func removeComicFromMyFavorite(_ comic : Comic){
        let defaults = UserDefaults.standard
        let favorites = (defaults.object(forKey: "favorite_list") as! NSMutableArray).mutableCopy() as! NSMutableArray
        for (index , c) in (favorites.enumerated()){
            let dict = c as! NSMutableDictionary
            if comic.getId() == dict.object(forKey: "comic_id") as! String {
                favorites.removeObject(at: index)
                break
            }
        }
        defaults.set(favorites, forKey: "favorite_list")
        defaults.synchronize()
    }
    
    static func listAllFavorite() -> NSMutableArray {
        let defaults = UserDefaults.standard
        var favorites = (defaults.object(forKey: "favorite_list") as! NSMutableArray).mutableCopy() as! NSMutableArray
        if favorites == nil {
            let favoriteList = NSMutableArray.init()
            favorites = favoriteList
            defaults.set(favoriteList, forKey: "favorite_list")
            defaults.synchronize()
        }
        return favorites
    }
    
    static func checkComicIsMyFavorite(_ comic:Comic) -> Bool{
        var isMyFavorite : Bool = false
        let defaults = UserDefaults.standard
        let favorites = defaults.object(forKey: "favorite_list") as! NSMutableArray
        let copyFavorites = favorites.mutableCopy() as! NSMutableArray
        for (_ , c) in (copyFavorites.enumerated()){
            let comicCopy = c as!NSMutableDictionary
            if comic.getId() == (comicCopy as AnyObject).object(forKey: "comic_id") as! String {
                isMyFavorite = true
            }
        }
        return isMyFavorite
    }
    
}
