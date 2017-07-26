//
//  Episode.swift
//  Pods
//
//  Created by ray.lee on 2017/6/7.
//
//

import Foundation

open class Episode{
    fileprivate var mName : String?// 漫畫每集(話)(卷)名稱
    fileprivate var mUrl : String?
    fileprivate var mCatid : String?
    fileprivate var mCopyright : String?
    fileprivate var mCh : Int?
    fileprivate var mChs : Int = 0
    fileprivate var mTi : Int = 0
    fileprivate var mPs : Int = 0 //漫畫總頁數
    fileprivate var mCs : String = ""
    fileprivate var mC : String = ""
    fileprivate var mImageUrl : [String] = [String]()//每頁漫畫圖片
    
    fileprivate let mF : Int = 50
    
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
     * 取得集數編號，例如1、2、3…
     */
    open func getCh() -> Int{
        return mCh!
    }
    
    open func setCh(_ ch : String) -> Void{
        mCh = Int(ch)
    }
    
    /*
     * 取得最新集數，例如最新第68號，此回傳值則為68
     */
    open func getChs() -> Int{
        return mChs
    }
    
    open func setChs(_ chs : Int) -> Void{
        mChs = chs
    }
    
    open func getTi() -> Int{
        return mTi
    }
    
    open func setTi(_ ti : Int) -> Void{
        mTi = ti
    }
    
    /*
     * 取得單集漫畫混淆過的編碼
     */
    open func getCs() -> String{
        return mCs
    }
    
    open func setCs(_ cs : String) -> Void{
        mCs = cs
    }
    
    //讀取1話(集、卷)全部漫畫圖片網址
    open func setUpPages(){
        sp()
        let totalPage = mPs
        
        for i in 0..<totalPage {
            mImageUrl.append(si( i + 1))
        }
    }
    
    /*
     * 取得單集(話、卷)圖片總頁數
     */
    open func getPages() -> Int{
        return mPs
    }
    
    /*
     * 取得單集(話、卷)全部圖片下載網址，張數等同getPages()
     */
    open func getImageUrlList() -> [String]{
        return mImageUrl
    }
    
    fileprivate func sp(){
        let cc : Int = mCs.lengthOfBytes(using: .ascii)
        
        for i in 0..<(cc / mF){
            if(ss(mCs, i * mF, 4) == (String(mCh!))){
                mC = ss(mCs, i * mF, mF, mF)
                break;
            }
        }
        
        if(mC.isEmpty){
            mC = ss(mCs, cc - mF, mF)
            mCh = mChs
        }
        
        let ps : String = ss(mC, 7, 3)
        
        if (!ps.isEmpty){
            mPs = Int(ps)!
        }
    }
    
    fileprivate func ss(_ a : String, _  b : Int, _  c : Int) -> String{
        return ss(a, b, c, nil)
    }
    
    fileprivate func ss(_ a : String, _  b : Int, _  c : Int, _  d : Int?) -> String{
        let e : String = StringUtility.substring(a, b, b + c)
        
        return d == nil ? e.replacingOccurrences(of: "[a-z]", with: "", options: .regularExpression, range: nil) : e
    }
    
    fileprivate func si(_ p : Int) -> String{
        let ssStr1 : String = ss(mC, 4, 2)
        let ssStr2 : String = ss(mC, 6, 1)
        let ssStr3 : String = ss(mC, 0, 4)
        let ssStr4 : String = ss(mC, mm(p) + 10, 3, mF)

        return "http://img" + ssStr1 + ".8comic.com/" + ssStr2 + "/"
            + String(mTi) + "/" + ssStr3 + "/" + String(nn(p)) + "_"
            + ssStr4 + ".jpg"
    }
    
    fileprivate func mm(_ p : Int) -> Int{
        return (((p - 1) / 10) % 10) + (((p - 1) % 10) * 3)
    }
    
    fileprivate func nn(_ n : Int) -> String{
        if (n < 10){
            return "00" + String(n)
        }else{
            if (n < 100){
                return "0" + String(n)
            }else{
                return String(n)
            }
        }
    }
}
