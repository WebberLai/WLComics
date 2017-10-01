# Swift8ComicSDK

[![CI Status](http://img.shields.io/travis/RayTW/Swift8ComicSDK.svg?style=flat)](https://travis-ci.org/RayTW/Swift8ComicSDK)
[![Version](https://img.shields.io/cocoapods/v/Swift8ComicSDK.svg?style=flat)](http://cocoapods.org/pods/Swift8ComicSDK)
[![License](https://img.shields.io/cocoapods/l/Swift8ComicSDK.svg?style=flat)](http://cocoapods.org/pods/Swift8ComicSDK)
[![Platform](https://img.shields.io/cocoapods/p/Swift8ComicSDK.svg?style=flat)](http://cocoapods.org/pods/Swift8ComicSDK)

## Requirements

* 必須要在 app 啟動時，先呼叫 R8Comic.get().loadSiteUrlList(…)，以取得該站漫畫圖片存放的伺服器列表。
* 信任全部 http 開頭的網址，因無法明確得知此網站存放漫畫的主機 domain，請在 info.plist 加上下列設定：

```xml
<key>NSAppTransportSecurity</key>
<dict>
	<key>NSAllowsArbitraryLoads</key>
	<true/>
</dict>
```

## Installation

Swift8ComicSDK is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "Swift8ComicSDK"
```

### Swift language version

* version <= v1.2.3 swift 3.2
* version >= v2.0.0 swift 4

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

### Class R8Comic, for example

讀取全部漫畫

```swift
R8Comic.get().getAll { (comics:[Comic]) in
    self.mComics = comics
    for comic : Comic  in comics {
        print("id==>\(comic.getId()), name[\(comic.getName())]")
    }
}
```
	
搜尋漫畫

```swift
R8Comic.get().searchComic("火影") { (comics) in
    print("searchComic=>\(comics.count)")
            
    for comicTemp : Comic  in comics {
        print("id==>\(comicTemp.getId()), name[\(comicTemp.getName())]")
    }
}
```

快速搜尋漫畫

```swift
R8Comic.get().quickSearchComic("火影") { (comics) in
    print("testQuickSearchComic=>\(comics.count)")
            
    for comicName : String  in comics {
        print("name[\(comicName)]")
    }
}
```

讀取指定一款漫畫的資訊

```swift
let comic = R8Comic.get().generatorFakeComic("103", name: "海賊王")
    
R8Comic.get().loadComicDetail(comic) { (comicDetail : Comic) in
    print("loadFinish,id==>\(comicDetail.getId()), name[\(comicDetail.getName())]")
            
    print("comic,Description=>\(comic.getDescription()!)")
    print("comic,Author=>\(comic.getAuthor()!)")
    print("comic,UpdateTime=>\(comic.getLatestUpdateDateTime()!)")
    print("comic,EpisodeCount=>\(comic.getEpisode().count)")
}
```

完整流程範例

```swift
R8Comic.get().loadSiteUrlList { (hostMap: [String: String]) in
     //self.mHostMap = hostMap
     
     // 取得全部漫畫
     R8Comic.get().getAll { (comics: [Comic]) in
         self.mComics = comics
         let comic = comics[comics.count - 1]
         
         print("comic,id==>\(comic.getId()), name[\(comic.getName())]")
         print("comic,封面大圖==>\(String(describing:comic.getIconUrl())), 封面小圖[\(String(describing:comic.getSmallIconUrl()))]")
         
         // 單1本漫畫，解析說明、集數等等資料…
         R8Comic.get().loadComicDetail(comic, onLoadDetail: { (comic) in
             
             print("comic,集數==>\(comic.getEpisode().count)")
             // 單集漫畫讀取圖片網址資料
             let episode = comic.getEpisode()[0]
             //檢查此漫畫集數是否已有串過完整url，若未有完成url則將url重組
             if(!episode.getUrl().hasPrefix("http")){
                 episode.setUrl(hostMap[episode.getCatid()]! + episode.getUrl())
             }
             
             print("comic,episode名稱==>\(episode.getName())")
             
             print("comic,episode,url==>\(episode.getUrl())")
             
             R8Comic.get().loadEpisodeDetail(episode, onLoadDetail: { (episode) in
                 
                 episode.setUpPages()
                 
                 print("episode,單集多張圖片網址=>\(episode.getImageUrlList())")
             })
         })
     }
 }
```

## Note

* 必須要在 app 啟動時，先呼叫 R8Comic.get().loadSiteUrlList(…)，以取得該站漫畫圖片存放的伺服器列表。

## Author

RayTW, ray00000sina@gmail.com

## License

Swift8ComicSDK is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
