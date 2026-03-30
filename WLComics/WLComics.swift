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
        // 先從 plist 快取讀取，立即顯示
        if let cached = restoreComicsFromPlist(), !cached.isEmpty {
            mAllComics = cached
            onLoadedComics(cached)
            // 背景更新
            mR8Comic.getAll { (comics:[Comic]) in
                guard !comics.isEmpty else { return }
                self.mAllComics = comics
                self.storeComicsToPlist(comics: comics)
            }
        } else {
            // 無快取，從網路載入
            mR8Comic.getAll { (comics:[Comic]) in
                self.mAllComics = comics
                self.storeComicsToPlist(comics: comics)
                onLoadedComics(comics)
            }
        }
    }

    fileprivate func restoreComicsFromPlist() -> [Comic]? {
        guard let array = SwiftyPlistManager.shared.fetchValue(for: "comics", fromPlistWithName: "AllComics") as? [[String: String]],
              !array.isEmpty else { return nil }
        return array.compactMap { dict -> Comic? in
            guard let id = dict["comic_id"], let name = dict["name"] else { return nil }
            let comic = mR8Comic.generatorFakeComic(id, name: name)
            // 用 ID 重新產生 URL，避免快取中殘留舊格式網址
            comic.setIconUrl(mR8Comic.getComicIconUrl(id))
            comic.setSmallIconUrl(mR8Comic.getComicSmallIconUrl(id))
            return comic
        }
    }

    fileprivate func storeComicsToPlist(comics: [Comic]) {
        let array = comics.map { comic -> [String: String] in
            var dict = ["comic_id": comic.getId(), "name": comic.getName()]
            if let url = comic.getIconUrl() { dict["icon_url"] = url }
            return dict
        }
        SwiftyPlistManager.shared.save(array, forKey: "comics", toPlistWithName: "AllComics") { _ in }
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
