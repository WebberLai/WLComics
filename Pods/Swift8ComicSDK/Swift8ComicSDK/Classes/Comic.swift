//
//  Comic.swift
//  Pods
//
//  Created by ray.lee on 2017/6/7.
//
//

import Foundation

open class Comic{
    private var mId : String? // 漫畫編號
    private var mIconUrl : String? // 漫畫封面大圖網址
    private var mSmallIconUrl : String? // 漫畫封面小圖網址
    private var mName : String?// 漫畫名稱
    private var mAuthor : String?// 漫畫作者
    private var mLatestUpdateDateTime : String? //最後更新的時間
    private var mDescription : String? //漫畫描述
    private var mEpisodes = [Episode]() //漫畫集數列表
    
    open func getId() -> String{
        return mId!
    }
    
    open func getIconUrl() -> String?{
        return mIconUrl
    }
    
    open func getSmallIconUrl() -> String?{
        return mSmallIconUrl
    }
    
    open func getName() -> String{
        return mName!
    }
    
    open func getAuthor() -> String?{
        return mAuthor
    }
    
    open func getLatestUpdateDateTime() -> String?{
        return mLatestUpdateDateTime
    }
    
    open func getDescription() -> String?{
        return mDescription
    }
    
    open func getEpisode() -> [Episode]{
        return mEpisodes
    }
    
    open func setId(_ id : String) -> Void{
        mId = id
    }
    
    open func setIconUrl(_ url : String) -> Void{
        mIconUrl = url
    }
    
    open func setSmallIconUrl(_ url : String) -> Void{
        mSmallIconUrl = url
    }
    
    open func setName(_ name : String) -> Void{
        mName = name
    }
    
    open func setAuthor(_ author : String) -> Void{
        mAuthor = author
    }
    
    open func setLatestUpdateDateTime(_ time : String) -> Void{
        mLatestUpdateDateTime = time
    }
    
    open func setDescription(_ description : String) -> Void{
        mDescription = description
    }
    
    open func setEpisode(_ episode : [Episode]) -> Void{
        mEpisodes = episode
    }
}
