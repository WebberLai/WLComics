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
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        DropboxClientsManager.setupWithAppKey("8lpshpy2m2lq74j")
        SwiftyPlistManager.shared.start(plistNames:["MyFavoritesComics"], logging: false)
        SwiftyPlistManager.shared.start(plistNames:["AllComics"], logging: false)
        // Override point for customization after application launch.
        let splitViewController = window!.rootViewController as! UISplitViewController
        splitViewController.preferredDisplayMode = UISplitViewControllerDisplayMode.allVisible
        let navigationController = splitViewController.viewControllers[splitViewController.viewControllers.count-1] as! UINavigationController
        navigationController.topViewController!.navigationItem.leftBarButtonItem = splitViewController.displayModeButtonItem
        splitViewController.delegate = self
        
        WLComics.sharedInstance().setUp()
        return true
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
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if let authResult = DropboxClientsManager.handleRedirectURL(url) {
            switch authResult {
            case .success:
                print("Success! User is logged into Dropbox.")
            case .cancel:
                print("Authorization flow was manually canceled by user!")
            case .error(_, let description):
                print("Error: \(description)")
            }
        }
        return true
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

