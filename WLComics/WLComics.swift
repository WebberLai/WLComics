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
    
    init() {
        
    }
    
    open class func sharedInstance() -> WLComics{
        return sInstance
    }
    
    open func getR8Comic() -> R8Comic{
        return mR8Comic;
    }
    
    open func setUp() -> Void{
        R8Comic.get().loadSiteUrlList { (hostMap : [String : String]) in
            self.mHostMap = hostMap
        }
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
}
