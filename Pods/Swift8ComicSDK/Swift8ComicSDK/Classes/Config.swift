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
    private let mSmallIconUrl : String = mComicHost + "pics/0/%@s.jpg"
    private let mIconUrl : String = mComicHost + "pics/0/%@.jpg"
    private let mComicDetail : String = mComicHost + "html/%@.html"
    private let mQuickSearchUrl : String = mComicHost + "member/quicksearchjs.aspx?r=%.16f&t=item&o=id&k=%@"
    private let mSearchUrl : String = mComicHost + "member/search.aspx?k=%@&page=%d"
    
    open func getComicDetailUrl(_ comicId: String) -> String{
        return String(format: mComicDetail, comicId)
    }
    
    open func getComicIconUrl(_ comicId: String) -> String{
        return String(format: mIconUrl, comicId)
    }
    
    open func getComicSmallIconUrl(_ comicId: String) -> String{
        return String(format: mSmallIconUrl, comicId)
    }
    
    open func getQuickSearchUrl(_ keyword: String) -> String{
        return String(format: mQuickSearchUrl,(CGFloat(Float(arc4random()) / Float(UINT32_MAX))), StringUtility.urlEncodeUsingGB2312(keyword))
    }
    
    open func getSearchUrl(_ keyword: String, _ page : Int) -> String{
        return String(format: mSearchUrl, StringUtility.urlEncodeUsingBIG5(keyword), page)
    }
}
