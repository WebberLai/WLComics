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

    init() {
        // 限制同時下載數，避免 8comic 伺服器因並發過多而斷開連線 (Connection reset by peer)
        let config = ImageDownloader.default.sessionConfiguration
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 30
        ImageDownloader.default.sessionConfiguration = config
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

    // MARK: - 載入所有漫畫（從 bundle plist）

    open func loadAllComics(_ onLoadedComics: @escaping ([Comic]) -> Void) {
        // 在背景讀取 plist，避免阻塞主線程
        DispatchQueue.global(qos: .userInitiated).async {
            if let cached = self.restoreComicsFromPlist(), !cached.isEmpty {
                self.mAllComics = cached
                onLoadedComics(cached)
            } else {
                // plist 不存在時才從網路載入
                self.mR8Comic.getAll { (comics:[Comic]) in
                    self.mAllComics = comics
                    self.storeComicsToPlist(comics: comics)
                    onLoadedComics(comics)
                }
            }
        }
    }

    fileprivate func restoreComicsFromPlist() -> [Comic]? {
        guard let array = SwiftyPlistManager.shared.fetchValue(for: "comics", fromPlistWithName: "AllComics") as? [[String: String]],
              !array.isEmpty else { return nil }
        return array.compactMap { dict -> Comic? in
            guard let id = dict["comic_id"], let name = dict["name"] else { return nil }
            let comic = mR8Comic.generatorFakeComic(id, name: name)
            comic.setIconUrl(mR8Comic.getComicIconUrl(id))
            comic.setSmallIconUrl(mR8Comic.getComicSmallIconUrl(id))
            return comic
        }
    }

    fileprivate func storeComicsToPlist(comics: [Comic]) {
        let array = comics.map { comic -> [String: String] in
            return ["comic_id": comic.getId(), "name": comic.getName()]
        }
        SwiftyPlistManager.shared.save(array, forKey: "comics", toPlistWithName: "AllComics") { _ in }
    }

    // MARK: - 搜尋漫畫（新 API）

    open func searchComics(keyword: String, _ onLoadedComics: @escaping ([Comic]) -> Void) {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.8comic.com/search/?key=\(encoded)") else {
            onLoadedComics([])
            return
        }

        var request = URLRequest(url: url)
        request.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let html = String(data: data, encoding: .utf8) else {
                onLoadedComics([])
                return
            }

            let comics = self.parseSearchResults(html)
            // 將搜尋到的新漫畫合併到 plist
            if !comics.isEmpty {
                self.mergeComicsToPlist(newComics: comics)
            }
            onLoadedComics(comics)
        }.resume()
    }

    /// 解析搜尋結果 HTML，提取漫畫 ID 和名稱
    /// 新版網站格式為多行結構：
    ///   <a href="/html/21673.html" class="...">
    ///     <li class="comicpic_col6_name ..."><font color=red>漫畫名稱</font></li>
    ///   </a>
    fileprivate func parseSearchResults(_ html: String) -> [Comic] {
        var comics = [Comic]()
        var seen = Set<String>()

        // 策略：先用 regex 找出所有 <a href="/html/ID.html"...>...</a> 區塊
        // 然後從區塊內的 comicpic_col6_name 行提取名稱
        let lines = html.components(separatedBy: "\n")
        var currentComicId: String? = nil

        for line in lines {
            // 檢查是否為包含漫畫連結的行
            if line.contains("href=\"/html/") && line.contains(".html\"") {
                // 提取 comic_id
                if let hrefStart = line.range(of: "href=\"/html/"),
                   let hrefEnd = line.range(of: ".html\"", range: hrefStart.upperBound..<line.endIndex) {
                    let comicId = String(line[hrefStart.upperBound..<hrefEnd.lowerBound])
                    if !comicId.isEmpty,
                       comicId.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil,
                       !seen.contains(comicId) {
                        // 嘗試舊格式：名稱在同一行最後一個 > 之後
                        if let nameStart = line.range(of: ">", options: .backwards) {
                            var name = String(line[nameStart.upperBound...])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if let tagStart = name.range(of: "<") {
                                name = String(name[name.startIndex..<tagStart.lowerBound])
                            }
                            if !name.isEmpty {
                                // 舊格式：名稱在同一行
                                seen.insert(comicId)
                                let comic = mR8Comic.generatorFakeComic(comicId, name: name)
                                comic.setIconUrl(mR8Comic.getComicIconUrl(comicId))
                                comic.setSmallIconUrl(mR8Comic.getComicSmallIconUrl(comicId))
                                comics.append(comic)
                                currentComicId = nil
                                continue
                            }
                        }
                        // 新格式：名稱在後續行，記下 ID 等後面的行來補名稱
                        currentComicId = comicId
                    }
                }
            }
            // 新格式：從 comicpic_col6_name 行提取名稱
            else if let comicId = currentComicId, line.contains("comicpic_col6_name") {
                // 移除所有 HTML 標籤取得純文字名稱
                var name = line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    seen.insert(comicId)
                    let comic = mR8Comic.generatorFakeComic(comicId, name: name)
                    comic.setIconUrl(mR8Comic.getComicIconUrl(comicId))
                    comic.setSmallIconUrl(mR8Comic.getComicSmallIconUrl(comicId))
                    comics.append(comic)
                }
                currentComicId = nil
            }
        }
        return comics
    }

    /// 將新搜尋到的漫畫合併到 plist（不重複）
    fileprivate func mergeComicsToPlist(newComics: [Comic]) {
        guard let existingArray = SwiftyPlistManager.shared.fetchValue(for: "comics", fromPlistWithName: "AllComics") as? [[String: String]] else { return }

        var existingIds = Set(existingArray.compactMap { $0["comic_id"] })
        var updatedArray = existingArray

        for comic in newComics {
            let id = comic.getId()
            if !existingIds.contains(id) {
                existingIds.insert(id)
                updatedArray.append(["comic_id": id, "name": comic.getName()])
            }
        }

        if updatedArray.count > existingArray.count {
            SwiftyPlistManager.shared.save(updatedArray, forKey: "comics", toPlistWithName: "AllComics") { _ in }
            // 更新記憶體中的列表
            if var all = mAllComics {
                for comic in newComics {
                    if !all.contains(where: { $0.getId() == comic.getId() }) {
                        all.append(comic)
                    }
                }
                mAllComics = all
            }
        }
    }

    // MARK: - 從分類頁面更新漫畫列表

    /// 背景爬取網站所有分類頁面，取得最新的完整漫畫列表，合併到 plist 後回傳更新後的全部漫畫
    open func refreshComicsFromWeb(onUpdated: @escaping ([Comic]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let baseUrl = "https://www.8comic.com"

            // Step 1: 取得首頁上的所有分類 ID
            guard let homepageData = self.fetchDataSync(url: baseUrl + "/"),
                  let homepageHtml = String(data: homepageData, encoding: .utf8) else {
                onUpdated(self.mAllComics ?? [])
                return
            }

            let categoryIds = self.parseCategoryIds(from: homepageHtml)
            guard !categoryIds.isEmpty else {
                onUpdated(self.mAllComics ?? [])
                return
            }

            // Step 2: 逐一爬取每個分類的所有頁面
            var allNewComics = [Comic]()
            var seen = Set<String>()

            for catId in categoryIds {
                guard let data = self.fetchDataSync(url: "\(baseUrl)/comic/\(catId)-1.html"),
                      let html = String(data: data, encoding: .utf8) else { continue }

                let maxPage = self.parseMaxPage(from: html, categoryId: catId)
                self.parseCategoryPageComics(html, seen: &seen, into: &allNewComics)

                var page = 2
                while page <= maxPage {
                    if let pageData = self.fetchDataSync(url: "\(baseUrl)/comic/\(catId)-\(page).html"),
                       let pageHtml = String(data: pageData, encoding: .utf8) {
                        self.parseCategoryPageComics(pageHtml, seen: &seen, into: &allNewComics)
                    }
                    page += 1
                }
            }

            // Step 3: 合併到 plist
            if !allNewComics.isEmpty {
                self.mergeComicsToPlist(newComics: allNewComics)
            }
            onUpdated(self.mAllComics ?? [])
        }
    }

    /// 同步抓取 URL 內容
    private func fetchDataSync(url urlString: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, error == nil,
               let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode {
                resultData = data
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return resultData
    }

    /// 從首頁 HTML 提取所有分類 ID（如 "4", "u", "65" 等）
    private func parseCategoryIds(from html: String) -> [String] {
        var ids = [String]()
        var seen = Set<String>()
        let lines = html.components(separatedBy: "\n")
        for line in lines {
            var searchStart = line.startIndex
            while let start = line.range(of: "/comic/", range: searchStart..<line.endIndex),
                  let end = line.range(of: "-1.html", range: start.upperBound..<line.endIndex) {
                let catId = String(line[start.upperBound..<end.lowerBound])
                if !catId.isEmpty && !seen.contains(catId) {
                    seen.insert(catId)
                    ids.append(catId)
                }
                searchStart = end.upperBound
            }
        }
        return ids
    }

    /// 從分類頁面的分頁元件解析最大頁數
    private func parseMaxPage(from html: String, categoryId: String) -> Int {
        var maxPage = 1
        let pattern = categoryId + "-"
        let lines = html.components(separatedBy: "\n")
        for line in lines {
            guard line.contains("pager") || line.contains(pattern) else { continue }
            var searchStart = line.startIndex
            while let start = line.range(of: pattern, range: searchStart..<line.endIndex) {
                guard let end = line.range(of: ".html", range: start.upperBound..<line.endIndex) else { break }
                if let pageNum = Int(line[start.upperBound..<end.lowerBound]) {
                    maxPage = max(maxPage, pageNum)
                }
                searchStart = end.upperBound
            }
        }
        return maxPage
    }

    /// 解析分類頁面中的漫畫
    /// 支援三種格式：
    ///   1. 舊格式：<a href="/html/XXX.html" target="_top">漫畫名</a>
    ///   2. 舊格式換行：<a href="/html/XXX.html" data-url="XXX" target="_top">漫畫名\n</a>
    ///   3. 卡片格式：<a href="/html/XXX.html" title="漫畫名" class="comicpic_col6...">
    private func parseCategoryPageComics(_ html: String, seen: inout Set<String>, into comics: inout [Comic]) {
        let lines = html.components(separatedBy: "\n")
        for line in lines {
            guard line.contains("href=\"/html/") && line.contains(".html\"") else { continue }

            guard let hrefStart = line.range(of: "href=\"/html/"),
                  let hrefEnd = line.range(of: ".html\"", range: hrefStart.upperBound..<line.endIndex) else { continue }
            let comicId = String(line[hrefStart.upperBound..<hrefEnd.lowerBound])
            guard !comicId.isEmpty,
                  comicId.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil,
                  !seen.contains(comicId) else { continue }

            var name = ""

            // 優先從 title 屬性取名稱（卡片格式）
            if let titleStart = line.range(of: "title=\""),
               let titleEnd = line.range(of: "\"", range: titleStart.upperBound..<line.endIndex) {
                name = String(line[titleStart.upperBound..<titleEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // 否則從最後一個 > 後面取名稱（舊格式）
            if name.isEmpty, let nameStart = line.range(of: ">", options: .backwards) {
                name = String(line[nameStart.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let tagStart = name.range(of: "<") {
                    name = String(name[name.startIndex..<tagStart.lowerBound])
                }
                name = name.replacingOccurrences(of: " (登入觀看)", with: "")
            }

            guard !name.isEmpty else { continue }

            seen.insert(comicId)
            let comic = mR8Comic.generatorFakeComic(comicId, name: name)
            comic.setIconUrl(mR8Comic.getComicIconUrl(comicId))
            comic.setSmallIconUrl(mR8Comic.getComicSmallIconUrl(comicId))
            comics.append(comic)
        }
    }

    // MARK: - 集數詳情

    open func loadEpisodeDetail(_ episode : Episode, onLoadDetail: @escaping (Episode) -> Void){
        if(!episode.getUrl().hasPrefix("https")){
            episode.setUrl("https://www.8comic.com/view/" + episode.getUrl())
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
