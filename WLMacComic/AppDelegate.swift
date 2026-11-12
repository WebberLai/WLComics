//
//  AppDelegate.swift
//  WLMacComic
//
//  Created by Webber Lai on 2017/10/2.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 收藏、閱讀進度、閱讀模式與 iOS 共用同一套儲存與 iCloud KVS key
        SwiftyPlistManager.shared.start(plistNames: ["MyFavoritesComics"], logging: false)
        FavoriteComics.startCloudSync()
        ReadingProgress.startCloudSync()
        ReadingModeStore.startCloudSync()

        if let window = NSApp.windows.first {
            window.title = "漫畫"
            window.minSize = NSSize(width: 1120, height: 720)
            window.setContentSize(NSSize(width: 1480, height: 920))
            window.center()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}

