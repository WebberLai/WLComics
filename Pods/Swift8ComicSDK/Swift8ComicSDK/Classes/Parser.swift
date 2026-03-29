//
//  Parser.swift
//  Pods
//
//  Created by ray.lee on 2017/6/8.
//  Updated: 2026/03 - 適配 8comic.com 新版 HTML 結構
//

import Foundation


open class Parser{
    // comicDetail - cview 解析
    let mFindCview = "cview("
    let mNameTag = ");return"

    // episodeDetail
    let mStartTagChs = "var chs="
    let mEndTagChs = ";var ti="
    let mStartTagTi = "var ti="
    let mEndTagTi = ";"
    let mStartTagCs = "var cs='"
    let mEndTagCs = "';for(var"
    let mEndTagCsAlt = "';var"

    // cviewJS
    let mStartTag = "if(catid"
    let mEndTag = "baseurl=\""
    let mUrlEndTag = "\";"

    // searchComic
    let mComidIdBegin = "<a href=\"/html/"
    let mComidIdEnd = ".html\">"
    let mComidNameBegin = "<b><font color=\"#0099CC\">"
    let mComidNameEnd = "</font></b>"
    let mPageBegin = "&page="
    let mPageEnd = "\"><img src=/images/pagelast.gif"

    public init() {
    }

    // MARK: - 漫畫列表（從 /comic/ 頁面解析）
    // HTML 格式: <a href="/html/ID.html" title="名稱"><img src="/pics/0/ID.jpg"><span>N集</span><span>名稱</span></a>
    open func allComics(_ htmlString : String, _ config: Config) -> [Comic]{
        var comicAry = [Comic]()
        var addedIds = Set<String>()

        // 用正則匹配 <a href="/html/ID.html" title="NAME">
        var searchFrom = htmlString.startIndex
        let hrefPattern = "href=\"/html/"
        let hrefEnd = ".html\""

        while let hrefStart = htmlString.range(of: hrefPattern, range: searchFrom..<htmlString.endIndex) {
            // 取出 ID
            let idStart = hrefStart.upperBound
            guard let idEndRange = htmlString.range(of: hrefEnd, range: idStart..<htmlString.endIndex) else { break }
            let comicId = String(htmlString[idStart..<idEndRange.lowerBound])

            // 移動搜尋位置
            searchFrom = idEndRange.upperBound

            // 驗證 ID 是數字
            guard !comicId.isEmpty, comicId.allSatisfy({ $0.isNumber }), !addedIds.contains(comicId) else { continue }

            // 取出 title="NAME"
            let searchEnd = htmlString.index(searchFrom, offsetBy: min(500, htmlString.distance(from: searchFrom, to: htmlString.endIndex)))
            var comicName = ""
            if let titleStart = htmlString.range(of: "title=\"", range: searchFrom..<searchEnd) {
                let nameStart = titleStart.upperBound
                if let titleEnd = htmlString.range(of: "\"", range: nameStart..<searchEnd) {
                    comicName = String(htmlString[nameStart..<titleEnd.lowerBound])
                }
            }

            // fallback: 從第二個 <span> 取名稱
            if comicName.isEmpty {
                if let firstSpanEnd = htmlString.range(of: "</span>", range: searchFrom..<searchEnd),
                   let secondSpanStart = htmlString.range(of: "<span>", range: firstSpanEnd.upperBound..<searchEnd),
                   let secondSpanEnd = htmlString.range(of: "</span>", range: secondSpanStart.upperBound..<searchEnd) {
                    comicName = String(htmlString[secondSpanStart.upperBound..<secondSpanEnd.lowerBound])
                }
            }

            guard !comicName.isEmpty else { continue }

            addedIds.insert(comicId)
            let comic = Comic()
            comic.setId(comicId)
            comic.setName(comicName)
            comic.setIconUrl(config.getComicIconUrl(comicId))
            comic.setSmallIconUrl(config.getComicSmallIconUrl(comicId))
            comicAry.append(comic)
        }

        print("Parser.allComics: parsed \(comicAry.count) comics from /comic/ page")
        return comicAry
    }

    // MARK: - 漫畫詳情（用 <meta> 標籤 + cview() 解析章節）
    open func comicDetail(htmlString : String, comic : Comic) -> Comic{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")

        var episodes = [Episode]()

        // 先從 <meta> 標籤取得漫畫資訊
        for txt in html {
            if comic.getAuthor() == nil {
                // <meta name="author" content="尾田榮一郎" />
                if let author = extractMetaContent(txt, name: "author") {
                    comic.setAuthor(author)
                }
                // 舊格式 fallback: 作者: XXX
                if let range = txt.range(of: "item-info-author") {
                    let after = String(txt[range.upperBound...])
                    let cleaned = self.replaceTag(after).replacingOccurrences(of: "作者: ", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        comic.setAuthor(cleaned)
                    }
                }
            }
            if comic.getLatestUpdateDateTime() == nil {
                // <meta name="date" content="2026-03-28" />
                if let date = extractMetaContent(txt, name: "date") {
                    comic.setLatestUpdateDateTime(date)
                }
                // 舊格式 fallback
                if let range = txt.range(of: "item-info-date") {
                    let after = String(txt[range.upperBound...])
                    let cleaned = self.replaceTag(after).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        comic.setLatestUpdateDateTime(cleaned)
                    }
                }
            }
        }

        // 解析 cview() 取得章節列表
        // 格式: onclick="cview('103-1.html',6,1);return false;"
        for i in 0..<html.count {
            let txt = html[i]

            // 用 StringUtility 安全取出 cview(...) 之間的內容
            guard let data_raw = StringUtility.substring(txt, "cview(", ");return") else { continue }
            var data = data_raw.replacingOccurrences(of: "'", with: "")
            let dataAry = data.components(separatedBy: ",")

            guard dataAry.count >= 3 else { continue }

            let parts = dataAry[0].components(separatedBy: "-")
            guard parts.count >= 2 else { continue }

            let ch = parts[1].replacingOccurrences(of: ".html", with: "")
            let url = dataAry[0]
                .replacingOccurrences(of: ".html", with: "")
                .replacingOccurrences(of: "-", with: ".html?ch=")
            let catid = dataAry[1].trimmingCharacters(in: .whitespaces)
            let copyright = dataAry[2].trimmingCharacters(in: .whitespaces)

            // 取得章節名稱（在下一行的 </a> 前）
            var episodeName = ""
            if i + 1 < html.count {
                episodeName = html[i + 1]
                episodeName = self.removeScriptsTag(episodeName)
                episodeName = self.replaceTag(episodeName)
                episodeName = episodeName.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if !episodeName.isEmpty {
                let episode = Episode()
                episode.setName(episodeName)
                episode.setUrl(url)
                episode.setCatid(catid)
                episode.setCopyright(copyright)
                episode.setCh(ch)
                episodes.append(episode)
            }
        }

        comic.setEpisode(episodes)
        return comic
    }

    // MARK: - 從 <meta> 標籤取值
    private func extractMetaContent(_ line: String, name: String) -> String? {
        let pattern = "name=\"\(name)\" content=\""
        guard let start = line.range(of: pattern) else { return nil }
        let after = String(line[start.upperBound...])
        guard let end = after.range(of: "\"") else { return nil }
        let value = String(after[..<end.lowerBound])
        return value.isEmpty ? nil : value
    }

    // MARK: - comicview.js 解析
    open func cviewJS(_ htmlString : String) -> [String: String]{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")

        var cviewMap = [String: String]()

        for txt in html {
            let tempText = txt.replacingOccurrences(of: ")", with: "")

            guard !tempText.isEmpty else { continue }

            guard let startTagUpper = StringUtility.indexOfUpper(source: tempText, search: mStartTag),
                  let endTagLower = StringUtility.indexOfLower(source: tempText, search: mEndTag),
                  startTagUpper < endTagLower else { continue }

            let numCode = StringUtility.substring(source: tempText, upper: startTagUpper, lower: endTagLower)
            let numCodeAry = StringUtility.split(numCode, separatedBy: "||")

            guard let urlStartTagUpper = StringUtility.indexOfUpper(source: tempText, search: mEndTag),
                  let urlEndTagLower = StringUtility.indexOfLower(source: tempText, search: mUrlEndTag),
                  urlStartTagUpper < urlEndTagLower else { continue }

            let cviewUrl = StringUtility.trim(
                StringUtility.substring(source: tempText, upper: urlStartTagUpper, lower: urlEndTagLower)
            )

            for num in numCodeAry {
                let tempNum = StringUtility.split(num, separatedBy: "==")
                guard tempNum.count >= 2 else { continue }
                cviewMap.updateValue(cviewUrl, forKey: StringUtility.trim(tempNum[1]))
            }
        }

        return cviewMap
    }

    // MARK: - 章節圖片頁面解析
    // 新版網站 var cs= 已被混淆（如 var m66z11='...'），需動態尋找最長字串變數
    open func episodeDetail(_ htmlString : String, episode : Episode) -> Episode{
        let html : [String] = StringUtility.split(htmlString, separatedBy: "\n")

        print("Parser.episodeDetail: total lines=\(html.count)")

        var foundSource = false

        for txt in html {
            // 找含有 var chs= 的行 — 這是包含所有解碼邏輯的 inline JS
            guard txt.contains("var chs=") else { continue }

            print("Parser.episodeDetail: found JS source line, length=\(txt.count)")

            // 用 regex 取 chs
            if let chsMatch = txt.range(of: "var chs=\\d+", options: .regularExpression) {
                let numStr = String(txt[chsMatch]).replacingOccurrences(of: "var chs=", with: "")
                if let chsInt = Int(numStr) {
                    episode.setChs(chsInt)
                    print("Parser.episodeDetail: chs=\(chsInt)")
                }
            }

            // 用 regex 取 ti
            if let tiMatch = txt.range(of: "var ti=\\d+", options: .regularExpression) {
                let numStr = String(txt[tiMatch]).replacingOccurrences(of: "var ti=", with: "")
                if let tiInt = Int(numStr) {
                    episode.setTi(tiInt)
                    print("Parser.episodeDetail: ti=\(tiInt)")
                }
            }

            // 整行 JS 傳給 JSnview，由 JSContext 執行
            episode.setSource(txt)
            foundSource = true
            print("Parser.episodeDetail: source set, ready for JSContext execution")
            break
        }

        if !foundSource {
            print("Parser.episodeDetail: WARNING - JS source line with 'var chs=' not found!")
        }

        return episode
    }

    /// 從 JS 中找出最長的字串變數值（即被混淆的 cs）
    /// cs 值的特徵：全部是英數字，無空格、括號、運算子等
    private func findLongestStringVar(_ js: String) -> String? {
        var longestValue: String? = nil
        var maxLen = 30 // 最少要 30 字元（一個 chunk 約 46~50 字元）

        // 掃描所有 var NAME='VALUE'; 模式（確保 =' 前面是變數名字元，避免匹配 ==''）
        var searchFrom = js.startIndex
        while let start = js.range(of: "='", range: searchFrom..<js.endIndex) {
            // 確保 =' 前面不是另一個 = （排除 =='）
            if start.lowerBound > js.startIndex {
                let before = js.index(before: start.lowerBound)
                if js[before] == "=" {
                    searchFrom = start.upperBound
                    continue
                }
            }

            let valueStart = start.upperBound
            guard let end = js.range(of: "';", range: valueStart..<js.endIndex) else { break }
            let value = String(js[valueStart..<end.lowerBound])

            // cs 值只包含英數字，不含空格、括號、分號、運算子等
            let isAlphanumeric = value.allSatisfy { $0.isLetter || $0.isNumber }
            if isAlphanumeric && value.count > maxLen {
                maxLen = value.count
                longestValue = value
                print("Parser.findLongestStringVar: candidate length=\(value.count), first20=\(String(value.prefix(20)))")
            }
            searchFrom = end.upperBound
        }

        return longestValue
    }

    /// 從 JS 中找出 chunk size（40~60 之間的整數變數）
    private func findChunkSize(_ js: String) -> Int? {
        // 尋找類似 var XXXXX=48; 的模式
        var searchFrom = js.startIndex
        let pattern = "var "
        while let start = js.range(of: pattern, range: searchFrom..<js.endIndex) {
            guard let eqSign = js.range(of: "=", range: start.upperBound..<js.endIndex),
                  let semicolon = js.range(of: ";", range: eqSign.upperBound..<js.endIndex) else { break }
            let value = String(js[eqSign.upperBound..<semicolon.lowerBound])
            if let num = Int(value), num >= 40 && num <= 60 {
                return num
            }
            searchFrom = semicolon.upperBound
        }
        return nil
    }

    // MARK: - 搜尋漫畫
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

            if comicId != nil {
                guard i + 9 < html.count else { continue }
                text = html[i + 9]
                comicName = StringUtility.substring(text, mComidNameBegin, mComidNameEnd)
                guard comicName != nil else { continue }
                comicName = self.replaceTag(comicName!)
                let comic = Comic()
                comic.setId(comicId!)
                comic.setName(comicName!)
                comic.setIconUrl(config.getComicIconUrl(comicId!))
                comic.setSmallIconUrl(config.getComicSmallIconUrl(comicId!))
                comics.append(comic)
            } else {
                comicName = nil

                if StringUtility.lastIndexOf(source: text, target: mPageBegin) != -1 {
                    let p = StringUtility.lastSubstring(text, mPageBegin, mPageEnd)
                    if let pVal = p, let tempPage = Int(pVal) {
                        maxPage = tempPage
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

    // MARK: - HTML Tag 處理

    open func replaceTag(_ txt : String) -> String{
        var ret = ""
        var insideTag = false

        for c in txt {
            if c == "<" {
                insideTag = true
            } else if c == ">" {
                insideTag = false
                continue
            }
            if insideTag { continue }
            if c == "\r" || c == "\n" { continue }
            ret.append(c)
        }

        return ret
    }

    open func removeScriptsTag(_ st : String) -> String{
        var ret = st
        let beginStr = "<script>"
        let endStr = "</script>"
        let lower = StringUtility.indexOfLower(source: st, search: beginStr)
        let upper = StringUtility.indexOfUpper(source: st, search: endStr)

        if upper != nil && lower != nil {
            ret = String(st[..<lower!]) + String(st[upper!...])
        }

        return ret
    }
}
