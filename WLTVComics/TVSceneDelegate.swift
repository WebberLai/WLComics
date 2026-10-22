//
//  TVSceneDelegate.swift
//  WLTVComics
//

import UIKit

class TVSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
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
}
