//
//  TVAppDelegate.swift
//  WLTVComics
//
//  tvOS App Delegate
//

import UIKit

@main
class TVAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        SwiftyPlistManager.shared.start(plistNames: ["MyFavoritesComics"], logging: false)
        FavoriteComics.startCloudSync()
        ReadingProgress.startCloudSync()

        // 每次 app 更新時，用 bundle 中最新的 AllComics.plist 覆蓋 Caches 的舊版
        refreshBundlePlistIfNeeded(name: "AllComics")
        SwiftyPlistManager.shared.start(plistNames: ["AllComics"], logging: false)

        WLComics.sharedInstance().setUp()
        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = TVSceneDelegate.self
        return config
    }

    /// 比對 bundle 版本，若 bundle 的 plist 較新則覆蓋 Caches 目錄的副本
    private func refreshBundlePlistIfNeeded(name: String) {
        let fileManager = FileManager.default
        guard let bundlePath = Bundle.main.path(forResource: name, ofType: "plist") else { return }
        let dir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        let docPath = (dir as NSString).appendingPathComponent("\(name).plist")

        let currentVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let versionKey = "\(name)_plist_version"
        let savedVersion = UserDefaults.standard.string(forKey: versionKey) ?? ""

        if currentVersion != savedVersion {
            try? fileManager.removeItem(atPath: docPath)
            try? fileManager.copyItem(atPath: bundlePath, toPath: docPath)
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
        }
    }
}
