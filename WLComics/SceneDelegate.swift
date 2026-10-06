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
                UpdateBadge.favoritesTabItem = tabBarController.viewControllers?
                    .first(where: SceneDelegate.isFavoritesTab)?.tabBarItem
            }
        }

        // 追蹤資料或收藏變動時更新分頁與 App 圖示的數字
        NotificationCenter.default.addObserver(forName: UpdateTracker.didChangeNotification,
                                               object: nil, queue: .main) { _ in UpdateBadge.refresh() }
        NotificationCenter.default.addObserver(forName: FavoriteComics.didChangeNotification,
                                               object: nil, queue: .main) { _ in UpdateBadge.refresh() }
        UpdateBadge.refresh()
        checkForUpdates()
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {
        checkForUpdates()
    }
    func sceneDidEnterBackground(_ scene: UIScene) {}

    // MARK: - 收藏更新

    /// 前景檢查：每天最多一次（節流在 UpdateChecker 內），結果只標示不推播
    private func checkForUpdates() {
        UpdateChecker.shared.check(reason: .foreground) { result in
            UpdateTracker.markNotified(comicIds: result.updates.map { $0.comicId })
        }
    }

    /// 點擊更新通知時切到「我的收藏」
    func showFavoritesTab() {
        guard let splitViewController = window?.rootViewController as? UISplitViewController,
              let tabBarController = splitViewController.viewControllers.first as? UITabBarController,
              let index = tabBarController.viewControllers?.firstIndex(where: SceneDelegate.isFavoritesTab) else { return }
        tabBarController.selectedIndex = index
    }

    private static func isFavoritesTab(_ viewController: UIViewController) -> Bool {
        return (viewController as? UINavigationController)?.viewControllers.first is FavoriteTableViewController
    }
}
