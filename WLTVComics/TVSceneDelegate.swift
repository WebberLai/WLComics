//
//  TVSceneDelegate.swift
//  WLTVComics
//

import UIKit

class TVSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        configureAppearance()
        if window == nil {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = storyboard.instantiateInitialViewController()
            self.window = window
            window.makeKeyAndVisible()
        } else {
            window?.windowScene = windowScene
        }
    }

    private func configureAppearance() {
        let accent = UIColor(red: 1.0, green: 0.48, blue: 0.34, alpha: 1)
        let tabs = UITabBarAppearance()
        tabs.configureWithDefaultBackground()
        tabs.backgroundColor = .black
        tabs.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        tabs.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = .secondaryLabel

        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.backgroundColor = .black
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white,
                                          .font: UIFont.systemFont(ofSize: 32, weight: .semibold)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().tintColor = accent
    }
}
