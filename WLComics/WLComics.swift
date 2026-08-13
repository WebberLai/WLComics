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

    /// 併發爬取上限。8comic 對大量並發會斷線，同時也避免佔滿執行緒。
    fileprivate static let maxConcurrentCrawlRequests = 4
    /// 單一分類最多爬幾頁，避免頁數解析出錯時無限爬下去
    fileprivate static let maxPagesPerCategory = 50

    /// mAllComics 會被多個背景執行緒讀寫（載入、搜尋、爬取），一律透過這個佇列存取
    fileprivate let stateQueue = DispatchQueue(label: "com.webberlai.WLComics.state")
    fileprivate var _mAllComics : [Comic]?
    /// 與 _mAllComics 同步維護的 id 集合，避免合併時做 O(n×m) 的線性查找
    fileprivate var _mAllComicIds = Set<String>()

    /// 目前的漫畫列表快照（執行緒安全）
    fileprivate func allComicsSnapshot() -> [Comic] {
        return stateQueue.sync { _mAllComics ?? [] }
    }

    fileprivate func setAllComics(_ comics: [Comic]) {
        stateQueue.sync {
            _mAllComics = comics
            _mAllComicIds = Set(comics.map { $0.getId() })
        }
    }

    /// 只加入尚未存在的漫畫，回傳實際新增的筆數
    @discardableResult
    fileprivate func appendNewComics(_ comics: [Comic]) -> Int {
        return stateQueue.sync {
            if _mAllComics == nil { _mAllComics = [] }
            var added = 0
            for comic in comics where !_mAllComicIds.contains(comic.getId()) {
                _mAllComicIds.insert(comic.getId())
                // 就地 append，避免每筆都重建整個陣列
                _mAllComics?.append(comic)
                added += 1
            }
            return added
        }
    }

    /// 統一在主執行緒回呼，呼叫端不必自己記得切執行緒
    fileprivate func deliverOnMain(_ comics: [Comic], to callback: @escaping ([Comic]) -> Void) {
        DispatchQueue.main.async { callback(comics) }
    }

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
                self.setAllComics(cached)
                self.deliverOnMain(cached, to: onLoadedComics)
            } else {
                // plist 不存在時才從網路載入
                self.mR8Comic.getAll { (comics:[Comic]) in
                    self.setAllComics(comics)
                    self.storeComicsToPlist(comics: comics)
                    self.deliverOnMain(comics, to: onLoadedComics)
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
            deliverOnMain([], to: onLoadedComics)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let html = String(data: data, encoding: .utf8) else {
                self.deliverOnMain([], to: onLoadedComics)
                return
            }

            let comics = self.parseSearchResults(html)
            // 將搜尋到的新漫畫合併到 plist（沒有新資料時不會寫檔）
            if !comics.isEmpty {
                self.mergeComicsToPlist(newComics: comics)
            }
            self.deliverOnMain(comics, to: onLoadedComics)
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
        // 快速路徑：記憶體列表已載入且沒有任何新 id 時直接返回，
        // 不必為了每次搜尋都讀取並解析一萬多筆的 plist
        let hasNothingNew = stateQueue.sync {
            _mAllComics != nil && newComics.allSatisfy { _mAllComicIds.contains($0.getId()) }
        }
        guard !hasNothingNew else { return }

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

        guard updatedArray.count > existingArray.count else { return }

        SwiftyPlistManager.shared.save(updatedArray, forKey: "comics", toPlistWithName: "AllComics") { _ in }
        // 更新記憶體中的列表：改用 id 集合比對，取代原本的 O(n×m) 線性查找
        appendNewComics(newComics)
    }

    // MARK: - 從分類頁面更新漫畫列表

    /// 背景爬取網站所有分類頁面，取得最新的完整漫畫列表，合併到 plist 後回傳更新後的全部漫畫
    open func refreshComicsFromWeb(onUpdated: @escaping ([Comic]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let baseUrl = "https://www.8comic.com"

            // Step 1: 取得首頁上的所有分類 ID
            guard let homepageData = self.fetchDataSync(url: baseUrl + "/"),
                  let homepageHtml = String(data: homepageData, encoding: .utf8) else {
                self.deliverOnMain(self.allComicsSnapshot(), to: onUpdated)
                return
            }

            let categoryIds = self.parseCategoryIds(from: homepageHtml)
            guard !categoryIds.isEmpty else {
                self.deliverOnMain(self.allComicsSnapshot(), to: onUpdated)
                return
            }

            // 原本是完全序列的爬取（分類 × 分頁，每個請求最久 15 秒），
            // 分類數乘上分頁數後可能跑上好幾分鐘。改成兩階段的有限併發。
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = WLComics.maxConcurrentCrawlRequests

            let lock = NSLock()
            var allNewComics = [Comic]()
            var seen = Set<String>()
            var pendingPages = [(catId: String, page: Int)]()

            // Step 2a: 併發抓每個分類的第一頁，同時取得該分類的總頁數
            for catId in categoryIds {
                queue.addOperation {
                    guard let data = self.fetchDataSync(url: "\(baseUrl)/comic/\(catId)-1.html"),
                          let html = String(data: data, encoding: .utf8) else { return }

                    // 夾住頁數上限，避免分頁解析出錯時無限爬下去
                    let maxPage = min(self.parseMaxPage(from: html, categoryId: catId),
                                      WLComics.maxPagesPerCategory)

                    lock.lock()
                    self.parseCategoryPageComics(html, seen: &seen, into: &allNewComics)
                    if maxPage >= 2 {
                        pendingPages.append(contentsOf: (2...maxPage).map { (catId: catId, page: $0) })
                    }
                    lock.unlock()
                }
            }
            queue.waitUntilAllOperationsAreFinished()

            // Step 2b: 併發抓剩下的所有分頁
            for target in pendingPages {
                queue.addOperation {
                    guard let data = self.fetchDataSync(url: "\(baseUrl)/comic/\(target.catId)-\(target.page).html"),
                          let html = String(data: data, encoding: .utf8) else { return }
                    lock.lock()
                    self.parseCategoryPageComics(html, seen: &seen, into: &allNewComics)
                    lock.unlock()
                }
            }
            queue.waitUntilAllOperationsAreFinished()

            // Step 3: 合併到 plist
            if !allNewComics.isEmpty {
                self.mergeComicsToPlist(newComics: allNewComics)
            }
            self.deliverOnMain(self.allComicsSnapshot(), to: onUpdated)
        }
    }

    /// 同步抓取 URL 內容
    private func fetchDataSync(url urlString: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let semaphore = DispatchSemaphore(value: 0)
        // callback 與呼叫端在不同執行緒，用 lock 保護寫入
        let resultLock = NSLock()
        var resultData: Data?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, error == nil,
               let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode {
                resultLock.lock()
                resultData = data
                resultLock.unlock()
            }
            semaphore.signal()
        }
        task.resume()

        // 加上逾時保險：callback 若因故沒被呼叫，不會讓這條執行緒永遠卡住
        if semaphore.wait(timeout: .now() + request.timeoutInterval + 5) == .timedOut {
            task.cancel()
            return nil
        }

        resultLock.lock()
        defer { resultLock.unlock() }
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
