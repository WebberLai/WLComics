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
