//
//  FavoriteComics.swift
//  WLComics
//
//  Created by Webber Lai on 2017/9/1.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import Swift8ComicSDK

class FavoriteComics: NSObject {

    private static let plistName = "MyFavoritesComics"
    private static let listKey = "favorite_list"

    /// 安全讀取收藏列表。plist 不存在或格式不符時回傳空陣列，不再 crash。
    private static func fetchFavorites() -> [NSMutableDictionary] {
        guard let raw = SwiftyPlistManager.shared.fetchValue(for: listKey, fromPlistWithName: plistName) else {
            return []
        }
        // 既有資料可能是 NSMutableDictionary 或 NSDictionary，統一轉成可變型別
        if let list = raw as? [NSMutableDictionary] {
            return list
        }
        if let list = raw as? [NSDictionary] {
            return list.map { NSMutableDictionary(dictionary: $0) }
        }
        return []
    }

    private static func saveFavorites(_ favorites: [NSMutableDictionary]) {
        SwiftyPlistManager.shared.save(favorites, forKey: listKey, toPlistWithName: plistName) { _ in
            //寫入檔案
        }
    }

    static func addComicToMyFavorite(_ comic: Comic) {
        var favorites = fetchFavorites()

        // 已收藏就不重複加入，避免產生移除不掉的重複項目
        let comicId = comic.getId()
        guard !favorites.contains(where: { $0.object(forKey: "comic_id") as? String == comicId }) else {
            return
        }

        let dict = NSMutableDictionary()
        dict.setObject(comic.getName(), forKey: "name" as NSCopying)
        dict.setObject(comicId, forKey: "comic_id" as NSCopying)
        // 封面網址可能為 nil，缺少時由讀取端用 comic_id 重新產生
        if let iconUrl = comic.getSmallIconUrl() {
            dict.setObject(iconUrl, forKey: "icon_url" as NSCopying)
        }

        favorites.append(dict)
        saveFavorites(favorites)
    }

    static func removeComicFromMyFavorite(_ comic: Comic) {
        let favorites = fetchFavorites()
        let comicId = comic.getId()

        // 移除所有符合的項目，清掉先前版本可能寫入的重複資料
        let remaining = favorites.filter { $0.object(forKey: "comic_id") as? String != comicId }

        guard remaining.count != favorites.count else { return }
        saveFavorites(remaining)
    }

    static func listAllFavorite() -> [NSMutableDictionary] {
        return fetchFavorites()
    }

    static func checkComicIsMyFavorite(_ comic: Comic) -> Bool {
        let comicId = comic.getId()
        // contains 找到就提早結束，不再掃完整個陣列
        return fetchFavorites().contains { $0.object(forKey: "comic_id") as? String == comicId }
    }

    static func getFavoritePlistData() -> Data? {
        let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = directoryURL.appendingPathComponent("\(plistName).plist")
        return try? Data(contentsOf: fileURL)
    }

}
