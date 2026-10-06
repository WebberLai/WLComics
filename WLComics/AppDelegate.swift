//
//  AppDelegate.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/26.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import BackgroundTasks
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?

    // Define identifier
    let notificationName = Notification.Name(rawValue:"BLEClickNotification")

    /// 需和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers（<bundle id>.checkUpdates）一致
    private static let updateTaskId = (Bundle.main.bundleIdentifier ?? "com.webberlai.WLComics") + ".checkUpdates"
    /// 漫畫多半是週刊，一天檢查一次就夠
    private static let updateInterval: TimeInterval = 24 * 60 * 60

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        SwiftyPlistManager.shared.start(plistNames:["MyFavoritesComics"], logging: false)
        FavoriteComics.startCloudSync()
        ReadingProgress.startCloudSync()
        UpdateTracker.startCloudSync()
        // 已有收藏的使用者，更新後第一次啟動時詢問通知權限（只會問一次）
        if !FavoriteComics.listAllFavorite().isEmpty {
            UpdateNotifier.requestAuthorizationIfNeeded()
        }
        UNUserNotificationCenter.current().delegate = self
        registerUpdateTask()
        scheduleUpdateTask()

        // 每次 app 更新時，用 bundle 中最新的 AllComics.plist 覆蓋 Documents 的舊版
        refreshBundlePlistIfNeeded(name: "AllComics")
        SwiftyPlistManager.shared.start(plistNames:["AllComics"], logging: false)

        WLComics.sharedInstance().setUp()
        return true
    }

    /// 比對 bundle 版本，若 bundle 的 plist 較新則覆蓋 Documents 目錄的副本
    private func refreshBundlePlistIfNeeded(name: String) {
        let fileManager = FileManager.default
        guard let bundlePath = Bundle.main.path(forResource: name, ofType: "plist") else { return }
        let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let docPath = (dir as NSString).appendingPathComponent("\(name).plist")

        // 用 app 版本號判斷是否需要覆蓋
        let currentVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let versionKey = "\(name)_plist_version"
        let savedVersion = UserDefaults.standard.string(forKey: versionKey) ?? ""

        if currentVersion != savedVersion {
            try? fileManager.removeItem(atPath: docPath)
            try? fileManager.copyItem(atPath: bundlePath, toPath: docPath)
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
        }
    }

    // MARK: - 背景檢查收藏更新

    private func registerUpdateTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppDelegate.updateTaskId, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleUpdateTask(task)
        }
    }

    private func scheduleUpdateTask() {
        let request = BGAppRefreshTaskRequest(identifier: AppDelegate.updateTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppDelegate.updateInterval)
        // Mac 或使用者關閉「背景 App 重新整理」時會失敗，此時只靠前景檢查
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 系統叫起背景任務時執行（在背景執行緒），檢查與通知都切回 main thread
    private func handleUpdateTask(_ task: BGAppRefreshTask) {
        scheduleUpdateTask()
        task.expirationHandler = {
            DispatchQueue.main.async { UpdateChecker.shared.cancel() }
        }
        DispatchQueue.main.async {
            UpdateChecker.shared.check(reason: .background) { result in
                UpdateNotifier.post(result.updates) {
                    UpdateBadge.refresh()
                    task.setTaskCompleted(success: true)
                }
            }
        }
    }

    // MARK: - 通知

    /// App 在前景時背景任務剛好跑完，仍顯示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 點擊更新通知時切到「我的收藏」
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix(UpdateNotifier.identifierPrefix) {
            let scene = UIApplication.shared.connectedScenes.first { $0.delegate is SceneDelegate }
            (scene?.delegate as? SceneDelegate)?.showFavoritesTab()
        }
        completionHandler()
    }

    // MARK: - UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags:[], action: #selector(AppDelegate.rightClick(command:)), discoverabilityTitle: "Next Page"),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow , modifierFlags:[], action: #selector(AppDelegate.leftClick(command:)), discoverabilityTitle: "Previous Page"),
        ]
        return commands
    }
    
    @objc func rightClick(command:UIKeyCommand) {
        NotificationCenter.default.post(name:notificationName,
                                        object: nil,
                                        userInfo: ["action":UIKeyCommand.inputRightArrow])
    }
    
    @objc func leftClick(command:UIKeyCommand) {
        NotificationCenter.default.post(name:notificationName,
                                        object: nil,
                                        userInfo: ["action":UIKeyCommand.inputLeftArrow])
    }
    
    
    // MARK: - Split view

    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController:UIViewController, onto primaryViewController:UIViewController) -> Bool {
        guard let secondaryAsNavController = secondaryViewController as? UINavigationController else { return false }
        guard let topAsDetailController = secondaryAsNavController.topViewController as? DetailViewController else { return false }
        if topAsDetailController.comicImages.count == 0 {
            // Return true to indicate that we have handled the collapse by doing nothing; the secondary controller will be discarded.
            return true
        }
        return false
    }

}

