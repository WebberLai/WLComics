//
//  UpdateNotifier.swift
//  WLComics
//

import UIKit
import UserNotifications

/// 收藏有新集數時發本地通知（只在背景檢查後使用）
enum UpdateNotifier {

    /// 通知 identifier 的前綴，點擊時用來判斷是不是更新通知
    static let identifierPrefix = "update."

    private static let askedKey = "update_notification_permission_asked"
    /// 超過這個數量就合併成一則
    private static let maxIndividual = 3

    /// 第一次需要時詢問通知權限，之後不再問（使用者可到設定自行開啟）
    static func requestAuthorizationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // 剛拿到 badge 權限時，把目前的數字補上 App 圖示
            DispatchQueue.main.async { UpdateBadge.refresh() }
        }
    }

    /// 發出通知並標記為已通知。completion 在 main thread 呼叫
    static func post(_ updates: [UpdateChecker.Update], completion: @escaping () -> Void) {
        guard !updates.isEmpty else {
            completion()
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                requests(for: updates).forEach { center.add($0) }
            }
            DispatchQueue.main.async {
                // 沒有權限也標記，避免日後開啟權限時一次補發舊的更新
                UpdateTracker.markNotified(comicIds: updates.map { $0.comicId })
                completion()
            }
        }
    }

    private static func requests(for updates: [UpdateChecker.Update]) -> [UNNotificationRequest] {
        if updates.count > maxIndividual {
            let content = UNMutableNotificationContent()
            content.title = "收藏有更新"
            content.body = "\(updates.count) 部收藏有更新"
            content.sound = .default
            return [UNNotificationRequest(identifier: identifierPrefix + "summary", content: content, trigger: nil)]
        }
        return updates.map { update in
            let content = UNMutableNotificationContent()
            content.title = update.comicName
            content.body = update.latestEpisodeName.map { "有新集數：\($0)" } ?? "有新集數"
            content.sound = .default
            return UNNotificationRequest(identifier: identifierPrefix + update.comicId, content: content, trigger: nil)
        }
    }
}

/// 「我的收藏」分頁與 App 圖示上的更新部數
enum UpdateBadge {

    /// 由 SceneDelegate 設定；背景啟動沒有畫面時為 nil，只更新 App 圖示
    static weak var favoritesTabItem: UITabBarItem?

    static func refresh() {
        let count = UpdateTracker.updatedComicCount()
        favoritesTabItem?.badgeValue = count > 0 ? "\(count)" : nil
        // 沒有 badge 權限時系統會直接忽略
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
}
