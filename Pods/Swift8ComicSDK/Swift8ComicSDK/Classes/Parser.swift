//
//  Parser.swift
//  Pods
//
//  Created by ray.lee on 2017/6/8.
//
//

import Foundation


open class Parser{
    //allComics
    let mCommicIdBegin = "showthumb("
    let mCommicIdEnd = ",this);"
    let mCommicNameBegin = "hidethumb();'>"
    let mCommicNameEnd = "</a></td>"
    let mFindCview = "cview("
    let mFindDeaitlTag = "style=\"line-height:25px\">"
    
    //comicDetail
    let mAuthorTag = "作者：</td>"
    let mUpdateTag = "更新：</td>"
    let mNameTag = ");return"
    
    //cviewJS
    let mStartTag = "if(catid"
    let mEndTag = "baseurl=\""
    let mUrlEndTag = "\";"
    
    //episodeDetail
    let mStartTagChs = "var chs="
    let mEndTagChs = ";var ti="
    let mStartTagTi = "var ti="
    let mEndTagTi = ";var cs="
    let mStartTagCs = "var cs='"
    let mEndTagCs = "';for(var"
    
    //searchComic
    let mComidIdBegin = "<a href=\"/html/"
    let mComidIdEnd = ".html\"><img src="
    let mComidNameBegin = "<b><font color=\"#0099CC\">"
    let mComidNameEnd = "</font></b>"
    let mPageBegin = "&page="
    let mPageEnd = "\"><img src=/images/pagelast.gif"
    
    public init() {
    }
    
    open func allComics(_ htmlString : String, _ config: Config) -> [Comic]{
        var html : String = htmlString
        var comicIdBeginIndex :String.Index?;
        var comicIdEndIndex :Range<String.Index>?;
        var comicId : String = "";
        var comicNameBeginIndex :String.Index?;
        var comicNameEndIndex :Range<String.Index>?;
        var comicName : String = "";
        
        
        var comicAry = [Comic]()
        
        while(true){
            comicIdBeginIndex = StringUtility.indexOfUpper(source: html, search: mCommicIdBegin)
            comicIdEndIndex = StringUtility.indexOf(source: html, search: mCommicIdEnd)
            
            if(comicIdBeginIndex == nil || comicIdEndIndex == nil){
                break
            }
            
            comicId = StringUtility.substring(source: html, upper: comicIdBeginIndex!, lower: comicIdEndIndex!.lowerBound)
            
            html = StringUtility.substring(source: html, beginIndex: comicIdEndIndex!.upperBound)
            comicNameBeginIndex = StringUtility.indexOfUpper(source: html, search: mCommicNameBegin)
            comicNameEndIndex = StringUtility.indexOf(source: html, search: mCommicNameEnd)
            
            if(comicNameBeginIndex == nil || comicNameEndIndex == nil){
                break
            }
            
            comicName = StringUtility.substring(source: html, upper: comicNameBeginIndex!, lower: comicNameEndIndex!.lowerBound)
            
            
            let comic = Comic()
            comic.setId(comicId)
            comic.setName(comicName)
            comic.setIconUrl(config.getComicIconUrl(comicId))
            comic.setSmallIconUrl(config.getComicSmallIconUrl(comicId))
            comicAry.append(comic)
        }
        
        
        return comicAry
    }
    
    open func comicDetail(htmlString : String, comic : Comic) -> Comic{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")
        
        var findCviewRange :Range<String.Index>?
        var findDetailTagRange :Range<String.Index>?;
        var findAuthorRange :Range<String.Index>?
        var latestUpdateTimeRange :Range<String.Index>?
        var nameTagRange :Range<String.Index>?
        var episodes = [Episode]() //建立集數物件
        
        for i in 0..<html.count {
            let txt : String = html[i]
            findCviewRange = StringUtility.indexOf(source: txt, search: mFindCview)
            
            //解析集數
            if(findCviewRange != nil){
                nameTagRange = StringUtility.indexOf(source: txt, search: mNameTag)
                
                var data = StringUtility.substring(source: txt, upper: (findCviewRange?.upperBound)!, lower: (nameTagRange?.lowerBound)!)
                data = data.replacingOccurrences(of: "'", with: "")
                let dataAry = StringUtility.split(data, separatedBy: ",") //集數圖片總張數參數
                
                let ch : String = StringUtility.split(dataAry[0], separatedBy: "-")[1].replacingOccurrences(of: ".html", with: "")
                let url : String = dataAry[0]
                    .replacingOccurrences(of: ".html", with: "")
                    .replacingOccurrences(of: "-", with: ".html?ch=")
                let catid : String = dataAry[1]
                let copyright : String = dataAry[2]
                
                if(nameTagRange == nil){
                    nameTagRange = StringUtility.indexOf(source: txt, search: mNameTag)
                    
                    if(nameTagRange != nil){
                        continue
                    }
                }
                //解析集數名稱
                if(nameTagRange != nil){
                    var episodeName = html[i + 1]
                    episodeName = self.removeScriptsTag(episodeName)
                    episodeName = self.replaceTag(episodeName)
                    episodeName = episodeName.replacingOccurrences(of: ":", with: ":")
                    episodeName = episodeName.replacingOccurrences(of: "\u{9}", with: "")
                    
                    if(!episodeName.isEmpty){
                        let episode = Episode()
                        episode.setName(episodeName)
                        episode.setUrl(url)
                        episode.setCatid(catid)
                        episode.setCopyright(copyright)
                        episode.setCh(ch)
                        
                        episodes.append(episode)
                    }
                }
            }else{
                //解析漫畫簡介
                if(comic.getDescription() == nil){
                    findDetailTagRange = StringUtility.indexOf(source: txt, search: mFindDeaitlTag)
                    
                    if(findDetailTagRange != nil){
                        let lower = StringUtility.indexOfLower(source: txt, search: "</td>")
                        comic.setDescription(StringUtility.substring(source: txt, upper: (findDetailTagRange?.upperBound)!, lower: lower!))
                    }
                }
                //解析作者
                if(comic.getAuthor() == nil){
                    if(findAuthorRange == nil){
                        findAuthorRange = StringUtility.indexOf(source: txt, search: mAuthorTag)
                        
                        if(findAuthorRange != nil){
                            continue
                        }
                    }
                    if(findAuthorRange != nil){
                        comic.setAuthor(self.replaceTag(txt))
                    }
                } else if(comic.getLatestUpdateDateTime() == nil){
                    //解析最新更新日期
                    if(latestUpdateTimeRange == nil){
                        latestUpdateTimeRange = StringUtility.indexOf(source: txt, search: mUpdateTag)
                        
                        if(latestUpdateTimeRange != nil){
                            continue
                        }
                    }
                    if(latestUpdateTimeRange != nil){
                        comic.setLatestUpdateDateTime(self.replaceTag(txt))
                    }
                }
            }
        }
        comic.setEpisode(episodes)
        
        return comic
    }
    
    open func cviewJS(_ htmlString : String) -> [String: String]{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")
        
        var startTagUpper : String.Index?
        var endTagLower : String.Index?
        let urlStratTag = mEndTag
        var urlStartTagUpper : String.Index?
        var urlEndTagLower : String.Index?
        
        var cviewMap = [String: String]()
        var tempText = ""
        
        for txt in html {
            tempText = txt.replacingOccurrences(of: ")", with: "")
            
            if(!tempText.isEmpty){
                startTagUpper = StringUtility.indexOfUpper(source: tempText, search: mStartTag)
                endTagLower = StringUtility.indexOfLower(source: tempText, search: mEndTag)
                
                if(startTagUpper != nil && endTagLower != nil){
                    let numCode : String = StringUtility.substring(source: tempText, upper: startTagUpper!, lower: endTagLower!)
                    let numCodeAry : [String] = StringUtility.split(numCode, separatedBy: "||")
                    urlStartTagUpper = StringUtility.indexOfUpper(source: tempText, search: urlStratTag)
                    urlEndTagLower = StringUtility.indexOfLower(source: tempText, search: mUrlEndTag)
                    var cviewUrl : String = StringUtility.substring(source: tempText, upper: urlStartTagUpper!, lower: urlEndTagLower!)
                    
                    cviewUrl = StringUtility.trim(cviewUrl)
                    
                    for num in numCodeAry{
                        let tempNum = StringUtility.split(num, separatedBy: "==")
                        cviewMap.updateValue(cviewUrl, forKey: StringUtility.trim(tempNum[1]))
                    }
                }
            }
        }
        
        
        return cviewMap
    }
    
    open func episodeDetail(_ htmlString : String, episode : Episode) -> Episode{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")
        
        
        for txt in html {
            let chs = StringUtility.substring(txt, mStartTagChs, mEndTagChs)
            let ti = StringUtility.substring(txt, mStartTagTi, mEndTagTi)
            let cs = StringUtility.substring(txt, mStartTagCs, mEndTagCs)
            
            if(chs != nil){
                episode.setChs(Int(chs!)!)
            }
            if(ti != nil){
                episode.setTi(Int(ti!)!)
            }
            if(cs != nil){
                episode.setCs(cs!)
                episode.setSource(txt)
                break
            }
        }
        
        return episode
    }
    
    open func searchComic(_ htmlString : String, onLoadComics: @escaping ([Comic]) -> Void, _ config: Config) -> Int{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")
        var comics = [Comic]()
        var text : String = ""
        var comicId : String?
        var comicName : String?
        var maxPage = 1
        
        for i in 0..<html.count {
            text = html[i]
            
            comicId = StringUtility.substring(text, mComidIdBegin, mComidIdEnd)
            
            if(comicId != nil){
                text = html[i + 1]
                comicName = StringUtility.substring(text, mComidNameBegin, mComidNameEnd)
                comicName = self.replaceTag(comicName!)
                let comic = Comic()
                comic.setId(comicId!)
                comic.setName(comicName!)
                comic.setIconUrl(config.getComicIconUrl(comicId!))
                comic.setSmallIconUrl(config.getComicSmallIconUrl(comicId!))
                comics.append(comic)
            }else{
                comicName = nil
                
                if(StringUtility.lastIndexOf(source: text, target: mPageBegin) != -1){
                    
                    let p = StringUtility.lastSubstring(text, mPageBegin, mPageEnd)
                    
                    if(p != nil){
                        if let tempPage = Int(p!){
                            maxPage = tempPage
                        }
                    }
                }
            }
        }
        
        onLoadComics(comics)
        
        return maxPage
    }
    
    open func quickSearchComic(_ htmlString : String) -> [String]{
        return StringUtility.split(htmlString, separatedBy: "|")
    }
    
    open func replaceTag(_ txt : String) -> String{
        var ret = ""
        let st = "<"
        let ed = ">"
        let charAry = txt.characters
        var check = false
        
        for c in charAry {
            if(c == st.characters.first){
                check = true
            }else if(c == ed.characters.first){
                check = false
                continue
            }
            if(check){
                continue
            }
            if(c == "\r" || c == "\n"){
                continue
            }
            ret.append(c)
        }
        
        return ret
    }
    
    open func removeScriptsTag(_ st : String) -> String{
        var ret = st
        let beginStr = "<script>"
        let endStr = "</script>"
        let lower : String.Index? = StringUtility.indexOfLower(source: st, search: beginStr)
        let upper : String.Index? = StringUtility.indexOfUpper(source: st, search: endStr)
        
        if(upper != nil && lower != nil){
            ret =  String(st[..<lower!]) + String(st[upper!...])
            //ret = st.substring(to: lower!) + st.substring(from: upper!)
        }
        
        return ret
    }
}


