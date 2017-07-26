//
//  Parser.swift
//  Pods
//
//  Created by ray.lee on 2017/6/8.
//
//

import Foundation


open class Parser{
    
    public init() {
    }
    
    open func allComics(_ htmlString : String, _ config: Config) -> [Comic]{
        var html : String = htmlString

        let commicIdBegin = "showthumb("
        let commicIdEnd = ",this);"
        var comicIdBeginIndex :String.Index?;
        var comicIdEndIndex :Range<String.Index>?;
        var comicId : String = "";
        
        let commicNameBegin = "hidethumb();'>"
        let commicNameEnd = "</a></td>"
        var comicNameBeginIndex :String.Index?;
        var comicNameEndIndex :Range<String.Index>?;
        var comicName : String = "";
        
        
        var comicAry = [Comic]()
        
        while(true){
            comicIdBeginIndex = StringUtility.indexOfUpper(source: html, search: commicIdBegin)
            comicIdEndIndex = StringUtility.indexOf(source: html, search: commicIdEnd)
            
            if(comicIdBeginIndex == nil || comicIdEndIndex == nil){
                break;
            }
            
            comicId = StringUtility.substring(source: html, upper: comicIdBeginIndex!, lower: comicIdEndIndex!.lowerBound)
            
            html = StringUtility.substring(source: html, beginIndex: comicIdEndIndex!.upperBound)
            comicNameBeginIndex = StringUtility.indexOfUpper(source: html, search: commicNameBegin)
            comicNameEndIndex = StringUtility.indexOf(source: html, search: commicNameEnd)
            
            if(comicNameBeginIndex == nil || comicNameEndIndex == nil){
                break;
            }

            comicName = StringUtility.substring(source: html, upper: comicNameBeginIndex!, lower: comicNameEndIndex!.lowerBound)
            

            let comic = Comic()
            comic.setId(comicId)
            comic.setName(comicName)
            comic.setIconUrl(config.getComicIconUrl(comicId))
            comic.setSmallIconUrl(config.getComicSmallIconUrl(comicId))
            comicAry.append(comic)
        }

        
        return comicAry;
    }

    open func comicDetail(htmlString : String, comic : Comic) -> Comic{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")
        
        let findCview = "cview("
        let findDeaitlTag = "style=\"line-height:25px\">"
        var findCviewRange :Range<String.Index>?
        var findDetailTagRange :Range<String.Index>?;
        let authorTag = "作者：</td>"
        var findAuthorRange :Range<String.Index>?
        let updateTag = "更新：</td>"
        var latestUpdateTimeRange :Range<String.Index>?
        let nameTag = ");return"
        var nameTagRange :Range<String.Index>?
        var episodes = [Episode]() //建立集數物件
        
        for i in 0..<html.count {
            let txt : String = html[i]
            findCviewRange = StringUtility.indexOf(source: txt, search: findCview)
            
            //解析集數
            if(findCviewRange != nil){
                nameTagRange = StringUtility.indexOf(source: txt, search: nameTag)
                
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
                    nameTagRange = StringUtility.indexOf(source: txt, search: nameTag)
                    
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
                    findDetailTagRange = StringUtility.indexOf(source: txt, search: findDeaitlTag)
                    
                    if(findDetailTagRange != nil){
                        let lower = StringUtility.indexOfLower(source: txt, search: "</td>")
                        comic.setDescription(StringUtility.substring(source: txt, upper: (findDetailTagRange?.upperBound)!, lower: lower!))
                    }
                }
                //解析作者
                if(comic.getAuthor() == nil){
                    if(findAuthorRange == nil){
                        findAuthorRange = StringUtility.indexOf(source: txt, search: authorTag)
                        
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
                        latestUpdateTimeRange = StringUtility.indexOf(source: txt, search: updateTag)
                        
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
 
        return comic;
    }
    
    open func cviewJS(_ htmlString : String) -> [String: String]{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")
        let startTag = "if(catid"
        let endTag = "baseurl=\""
        var startTagUpper : String.Index?
        var endTagLower : String.Index?
        
        let urlStratTag = endTag
        let urlEndTag = "\";"
        var urlStartTagUpper : String.Index?
        var urlEndTagLower : String.Index?
        
        var cviewMap = [String: String]()
        var tempText = ""
        
        for txt in html {
            tempText = txt.replacingOccurrences(of: ")", with: "")
            
            if(!tempText.isEmpty){
                startTagUpper = StringUtility.indexOfUpper(source: tempText, search: startTag)
                endTagLower = StringUtility.indexOfLower(source: tempText, search: endTag)
                
                if(startTagUpper != nil && endTagLower != nil){
                    let numCode : String = StringUtility.substring(source: tempText, upper: startTagUpper!, lower: endTagLower!)
                    let numCodeAry : [String] = StringUtility.split(numCode, separatedBy: "||")
                    urlStartTagUpper = StringUtility.indexOfUpper(source: tempText, search: urlStratTag)
                    urlEndTagLower = StringUtility.indexOfLower(source: tempText, search: urlEndTag)
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
        let startTagChs = "var chs="
        let endTagChs = ";var ti="
        let startTagTi = "var ti="
        let endTagTi = ";var cs="
        let startTagCs = "var cs='"
        let endTagCs = "';eval(unescape('"
        
        for txt in html {
            let chs = StringUtility.substring(source: txt, upperString: startTagChs, lowerString: endTagChs)
            let ti = StringUtility.substring(source: txt, upperString: startTagTi, lowerString: endTagTi)
            let cs = StringUtility.substring(source: txt, upperString: startTagCs, lowerString: endTagCs)
            
            
            if(chs != nil){
                episode.setChs(Int(chs!)!)
            }
            if(ti != nil){
               episode.setTi(Int(ti!)!)
            }
            if(cs != nil){
                episode.setCs(cs!)
                break
            }
        }
    
        return episode
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
            ret = st.substring(to: lower!) + st.substring(from: upper!)
        }
        
        return ret
    }
}


