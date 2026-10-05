//
//  SceneDelegate.swift
//  WLComics
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 如果 storyboard 沒自動建立 window，手動建立
        if window == nil {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = storyboard.instantiateInitialViewController()
            self.window = window
            window.makeKeyAndVisible()
        } else {
            window?.windowScene = windowScene
        }

        // 設定 SplitViewController
        if let splitViewController = window?.rootViewController as? UISplitViewController,
           let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            splitViewController.preferredDisplayMode = .allVisible
            // iOS 26 起 split view 會自己顯示側邊欄按鈕，再手動加一次會多出一顆空白的圓形按鈕
            if #unavailable(iOS 26),
               let navigationController = splitViewController.viewControllers.last as? UINavigationController {
                navigationController.topViewController?.navigationItem.leftBarButtonItem = splitViewController.displayModeButtonItem
            }
            splitViewController.delegate = appDelegate

            // 第三個 tab「已下載」：離線時從這裡進入閱讀
            if let tabBarController = splitViewController.viewControllers.first as? UITabBarController {
                let downloads = UINavigationController(rootViewController: DownloadsViewController(style: .plain))
                downloads.tabBarItem = UITabBarItem(title: "已下載", image: UIImage(systemName: "arrow.down.circle"), tag: 2)
                tabBarController.viewControllers = (tabBarController.viewControllers ?? []) + [downloads]
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
