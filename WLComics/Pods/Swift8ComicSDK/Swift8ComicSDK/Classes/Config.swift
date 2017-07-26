//
//  Config.swift
//  Pods
//
//  Created by ray.lee on 2017/6/7.
//
//

open class Config {
    open static let mComicHost : String = "http://www.comicbus.com/"
    open let mAllUrl : String = mComicHost + "comic/all.html"
    open let mCviewJSUrl : String = mComicHost + "js/comicview.js"
    fileprivate let mSmallIconUrl : String = mComicHost + "pics/0/%@s.jpg"
    fileprivate let mIconUrl : String = mComicHost + "pics/0/%@.jpg"
    fileprivate let mComicDetail : String = mComicHost + "html/%@.html"
    
    
    
    
    open func getComicDetailUrl(_ comicId: String) -> String{
        return String(format: mComicDetail, comicId)
    }
    
    open func getComicIconUrl(_ comicId: String) -> String{
        return String(format: mIconUrl, comicId)
    }
    
    open func getComicSmallIconUrl(_ comicId: String) -> String{
        return String(format: mSmallIconUrl, comicId)
    }
}
