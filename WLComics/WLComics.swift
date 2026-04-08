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
    fileprivate func parseSearchResults(_ html: String) -> [Comic] {
        var comics = [Comic]()
        var seen = Set<String>()

        // 格式: href="/html/10660.html" data-url="10660" target="_top">刃牙道
        // 或:   href="/html/103.html" target="_top" style="...">海賊王 (登入觀看)
        let lines = html.components(separatedBy: "\n")
        for line in lines {
            guard line.contains("href=\"/html/") && line.contains(".html\"") else { continue }

            // 提取 comic_id
            guard let hrefStart = line.range(of: "href=\"/html/"),
                  let hrefEnd = line.range(of: ".html\"", range: hrefStart.upperBound..<line.endIndex) else { continue }
            let comicId = String(line[hrefStart.upperBound..<hrefEnd.lowerBound])
            guard !comicId.isEmpty, comicId.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else { continue }
            guard !seen.contains(comicId) else { continue }
            seen.insert(comicId)

            // 提取名稱：最後一個 > 之後到 < 或行尾
            guard let nameStart = line.range(of: ">", options: .backwards) else { continue }
            var name = String(line[nameStart.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // 移除 HTML 尾標籤
            if let tagStart = name.range(of: "<") {
                name = String(name[name.startIndex..<tagStart.lowerBound])
            }
            // 移除 (登入觀看)
            name = name.replacingOccurrences(of: " (登入觀看)", with: "")
            guard !name.isEmpty else { continue }

            let comic = mR8Comic.generatorFakeComic(comicId, name: name)
            comic.setIconUrl(mR8Comic.getComicIconUrl(comicId))
            comic.setSmallIconUrl(mR8Comic.getComicSmallIconUrl(comicId))
            comics.append(comic)
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
