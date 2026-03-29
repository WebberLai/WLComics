//
//  WLComics.swift
//  WLComics
//
//  Created by Ray on 2017/7/30.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import Foundation
import Swift8ComicSDK
import Kingfisher

open class WLComics{
    fileprivate static let sInstance : WLComics = WLComics()
    fileprivate let mR8Comic : R8Comic = R8Comic.get()
    fileprivate var mHostMap : [String : String]?
    fileprivate var mAllComics :[Comic]?
    fileprivate static let KEY_ALL_COMICS : String = "allComics";
    
    enum ComicMemberNames: String {
        case ID = "mId"
        case NAME = "mName"
        case ICON_URL = "mIconUrl"
        case SMALL_ICON_URL = "mSmallIconUrl"
    }
    
    init() {
    }
    
    open class func sharedInstance() -> WLComics{
        return sInstance
    }
    
    open func getR8Comic() -> R8Comic{
        return mR8Comic;
    }
    
    open func setUp() -> Void{
        mR8Comic.loadSiteUrlList { (hostMap : [String : String]) in
            self.mHostMap = hostMap
        }
    }
    
    open func loadAllComics(_ onLoadedComics: @escaping ([Comic]) -> Void) {
        // 1. 先嘗試從 cache 載入，立即回傳
        if let cached = restoreComics(), !cached.isEmpty {
            mAllComics = cached
            onLoadedComics(cached)

            // 2. 背景更新 cache（不阻塞 UI）
            mR8Comic.getAll { (comics:[Comic]) in
                guard !comics.isEmpty else { return }
                self.mAllComics = comics
                self.storeComics(comics: comics)
            }
        } else {
            // 無 cache，從網路載入
            mR8Comic.getAll { (comics:[Comic]) in
                self.mAllComics = comics
                self.storeComics(comics: comics)
                onLoadedComics(comics)
            }
        }
    }
    
    //從UserDefaults將全部漫畫列表取出
    fileprivate func restoreComics() -> [Comic]?{
        guard let comicsData = UserDefaults.standard.object(forKey: WLComics.KEY_ALL_COMICS) as? [[String : String]] else {
            return nil
        }

        var comics = [Comic]()
        for comicDic in comicsData {
            guard let comicId = comicDic[ComicMemberNames.ID.rawValue],
                  let comicName = comicDic[ComicMemberNames.NAME.rawValue] else { continue }

            let comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(comicId, name: comicName)
            if let iconUrl = comicDic[ComicMemberNames.ICON_URL.rawValue] {
                comic.setIconUrl(iconUrl)
            }
            if let smallIconUrl = comicDic[ComicMemberNames.SMALL_ICON_URL.rawValue] {
                comic.setSmallIconUrl(smallIconUrl)
            }
            comics.append(comic)
        }

        return comics.isEmpty ? nil : comics
    }
    
    //將全部漫畫列表儲存到UserDefaults
    fileprivate func storeComics(comics : [Comic]){
        var comicsData = [[String : String]]()

        for comic in comics {
            var dict = [String : String]()
            dict[ComicMemberNames.ID.rawValue] = comic.getId()
            dict[ComicMemberNames.NAME.rawValue] = comic.getName()
            if let iconUrl = comic.getIconUrl() { dict[ComicMemberNames.ICON_URL.rawValue] = iconUrl }
            if let smallIconUrl = comic.getSmallIconUrl() { dict[ComicMemberNames.SMALL_ICON_URL.rawValue] = smallIconUrl }
            comicsData.append(dict)
        }

        UserDefaults.standard.set(comicsData, forKey: WLComics.KEY_ALL_COMICS)
    }
    
    open func loadEpisodeDetail(_ episode : Episode, onLoadDetail: @escaping (Episode) -> Void){
        //檢查此漫畫集數是否已有串過完整url，若未有完成url則將url重組
        if(!episode.getUrl().hasPrefix("https")){
            episode.setUrl("https://www.8comic.com/view/" + episode.getUrl())
        }
        mR8Comic.loadEpisodeDetail(episode, onLoadDetail: onLoadDetail)
    }
    
    //部份漫畫下載時，若client未帶Referer上去會被伺服器檔，造成無法正確下載圖片。 by Ray
    open func buildDownloadEpisodeHeader(_ episodeUrl : String) -> ImageDownloadRequestModifier{
        let modifier = AnyModifier { request in
            var r = request
            r.setValue(episodeUrl, forHTTPHeaderField: "Referer")
            return r
        }
        
        return modifier
    }
    
    //搜尋漫畫
    
    open func searchComics( keyword : String , _ onLoadedComics: @escaping ([Comic]) -> Void) {
        mR8Comic.searchComic(keyword) { (comics:[Comic]) in
            onLoadedComics(comics)
        }
    }
}
