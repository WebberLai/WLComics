//
//  Episode.swift
//  Pods
//
//  Created by ray.lee on 2017/6/7.
//
//

import Foundation

open class Episode{
    private var mName : String?// 漫畫每集(話)(卷)名稱
    private var mUrl : String?
    private var mCatid : String?
    private var mCopyright : String?
    private var mImageUrl : [String] = [String]()//每頁漫畫圖片
    private let mJSnview = JSnview();
    
    
    //讀取1話(集、卷)全部漫畫圖片網址
    open func setUpPages(){
        mImageUrl = mJSnview.setupPagesDownloadUrl()
    }
    
    /*
     * 取得單集漫畫名稱
     */
    open func getName() -> String{
        return mName!
    }
    
    /*
     * 設定單集漫畫名稱
     */
    open func setName(_ name : String) -> Void{
        mName = name
    }
    
    open func getUrl() -> String{
        return mUrl!
    }
    
    open func setUrl(_ url : String) -> Void{
        mUrl = url
    }
    
    open func getCatid() -> String{
        return mCatid!
    }
    
    open func setCatid(_ catid : String) -> Void{
        mCatid = catid
    }
    
    open func getCopyright() -> String{
        return mCopyright!
    }
    
    open func setCopyright(_ copyright : String) -> Void{
        mCopyright = copyright
    }
    
    /*
     * 取得單集(話、卷)全部圖片下載網址，張數等同getPages()
     */
    open func getImageUrlList() -> [String]{
        return mImageUrl
    }
    
    /*
     * 取得單集(話、卷)圖片總頁數
     */
    open func getPages() -> Int{
        return mImageUrl.count
    }
    
    open func setSource(_ source : String) -> Void{
        mJSnview.setSource(source)
    }
    
    open func setCs(_ cs : String) -> Void{
        mJSnview.setCs(cs)
    }
    
    open func setCh(_ ch : String) -> Void{
        mJSnview.setCh(ch)
    }
    open func setChs(_ chs : Int) -> Void{
        mJSnview.setChs(chs)
    }
    open func setTi(_ ti : Int) -> Void{
        mJSnview.setTi(ti)
    }
}
