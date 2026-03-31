//
//  AppDelegate.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/26.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit
import SwiftyDropbox

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate {

    var window: UIWindow?

    // Define identifier
    let notificationName = Notification.Name(rawValue:"BLEClickNotification")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DropboxClientsManager.setupWithAppKey("8lpshpy2m2lq74j")
        SwiftyPlistManager.shared.start(plistNames:["MyFavoritesComics"], logging: false)

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

    // MARK: - UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    func setupSplitViewController() {
        guard let splitViewController = window?.rootViewController as? UISplitViewController else { return }
        splitViewController.preferredDisplayMode = .allVisible
        let navigationController = splitViewController.viewControllers[splitViewController.viewControllers.count-1] as! UINavigationController
        navigationController.topViewController!.navigationItem.leftBarButtonItem = splitViewController.displayModeButtonItem
        splitViewController.delegate = self
    }
    
    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: UIKeyInputRightArrow, modifierFlags:[], action: #selector(AppDelegate.rightClick(command:)), discoverabilityTitle: "Next Page"),
            UIKeyCommand(input: UIKeyInputLeftArrow , modifierFlags:[], action: #selector(AppDelegate.leftClick(command:)), discoverabilityTitle: "Previous Page"),
        ]
        return commands
    }
    
    @objc func rightClick(command:UIKeyCommand) {
        NotificationCenter.default.post(name:notificationName,
                                        object: nil,
                                        userInfo: ["action":UIKeyInputRightArrow])
    }
    
    @objc func leftClick(command:UIKeyCommand) {
        NotificationCenter.default.post(name:notificationName,
                                        object: nil,
                                        userInfo: ["action":UIKeyInputLeftArrow])
    }
    
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        let canHandle = DropboxClientsManager.handleRedirectURL(url, includeBackgroundClient: false) { authResult in
            if let authResult = authResult {
                switch authResult {
                case .success:
                    print("Success! User is logged into Dropbox.")
                case .cancel:
                    print("Authorization flow was manually canceled by user!")
                case .error(_, let description):
                    print("Error: \(description)")
                }
            }
        }
        return canHandle
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

