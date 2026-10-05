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

    private static func saveFavorites(_ favorites: [NSMutableDictionary], pushToCloud: Bool = true) {
        SwiftyPlistManager.shared.save(favorites, forKey: listKey, toPlistWithName: plistName) { _ in
            //寫入檔案
        }
        if pushToCloud {
            cloudStore.set(favorites.map { $0 as NSDictionary }, forKey: listKey)
        }
    }

    // MARK: - iCloud 同步（NSUbiquitousKeyValueStore）

    /// 雲端收藏有變動、本地已更新時發出，畫面收到後重新讀取收藏
    static let didChangeNotification = Notification.Name("FavoriteComicsDidChange")

    private static let cloudStore = NSUbiquitousKeyValueStore.default
    /// 第一次啟用 iCloud 時要把本地既有收藏與雲端合併，之後以雲端為準
    private static let cloudMigratedKey = "favorite_icloud_migrated"

    /// 在 app 啟動時呼叫一次
    static func startCloudSync() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloudStore, queue: .main) { note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            switch reason {
            case NSUbiquitousKeyValueStoreServerChange:
                // 其他裝置改過收藏，直接採用雲端版本（才能正確反映刪除）
                applyCloudFavorites(merge: false)
            case NSUbiquitousKeyValueStoreInitialSyncChange, NSUbiquitousKeyValueStoreAccountChange:
                // 首次同步或換帳號，合併避免本地收藏被清掉
                applyCloudFavorites(merge: true)
            default:
                break
            }
        }
        cloudStore.synchronize()

        let migrated = UserDefaults.standard.bool(forKey: cloudMigratedKey)
        applyCloudFavorites(merge: !migrated)
        UserDefaults.standard.set(true, forKey: cloudMigratedKey)
    }

    private static func applyCloudFavorites(merge: Bool) {
        let cloud = (cloudStore.array(forKey: listKey) as? [NSDictionary])?.map { NSMutableDictionary(dictionary: $0) }
        let local = fetchFavorites()

        if merge {
            // 以 comic_id 取聯集，本地順序在前
            var seen = Set(local.compactMap { $0.object(forKey: "comic_id") as? String })
            var merged = local
            for item in cloud ?? [] {
                if let id = item.object(forKey: "comic_id") as? String, seen.insert(id).inserted {
                    merged.append(item)
                }
            }
            // 合併後若與雲端不同，推回雲端讓其他裝置也拿到
            if merged.count != (cloud?.count ?? 0) {
                saveFavorites(merged)
            } else if merged.count != local.count {
                saveFavorites(merged, pushToCloud: false)
            }
        } else {
            guard let cloud = cloud else { return }
            saveFavorites(cloud, pushToCloud: false)
        }

        NotificationCenter.default.post(name: didChangeNotification, object: nil)
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

}
