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
        mAllComics = restoreComics()
        
        if(mAllComics == nil){
            mR8Comic.getAll { (comics:[Comic]) in
                self.mAllComics = comics
                self.storeComics(comics: comics);
                
                onLoadedComics(self.mAllComics!)
            }
        }else{
            onLoadedComics(mAllComics!)
        }
    }
    
    //從UserDefaults將全部漫畫列表取出
    fileprivate func restoreComics() -> [Comic]?{
        var comics = [Comic]()
        let comicsData = UserDefaults.standard.object(forKey: WLComics.KEY_ALL_COMICS) as! [[String : String]]?
        
        guard comicsData == nil else {
            var comic : Comic? = nil
            
            for comicDic in comicsData! {
                let comicId = comicDic[ComicMemberNames.ID.rawValue]!
                let comicName = comicDic[ComicMemberNames.NAME.rawValue]!
                
                comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(comicId, name: comicName)
                comic?.setIconUrl(comicDic[ComicMemberNames.ICON_URL.rawValue]!)
                comic?.setSmallIconUrl(comicDic[ComicMemberNames.SMALL_ICON_URL.rawValue]!)
                comics.append(comic!)
            }
            
            return comics
        }
        
        return nil
    }
    
    //將全部漫畫列表儲存到UserDefaults
    fileprivate func storeComics(comics : [Comic]){
        var comicsData = [[String : String]]()
        
        for comic in comics {
            comicsData.append([ComicMemberNames.ID.rawValue : comic.getId(),
                               ComicMemberNames.NAME.rawValue : comic.getName(),
                               ComicMemberNames.ICON_URL.rawValue : comic.getIconUrl()!,
                               ComicMemberNames.SMALL_ICON_URL.rawValue : comic.getSmallIconUrl()!])
        }
        
        UserDefaults.standard.set(comicsData, forKey: WLComics.KEY_ALL_COMICS)
    }
    
    open func loadEpisodeDetail(_ episode : Episode, onLoadDetail: @escaping (Episode) -> Void){
        //檢查此漫畫集數是否已有串過完整url，若未有完成url則將url重組
        if(!episode.getUrl().hasPrefix("http")){
            episode.setUrl((mHostMap?[episode.getCatid()]!)! + episode.getUrl())
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
