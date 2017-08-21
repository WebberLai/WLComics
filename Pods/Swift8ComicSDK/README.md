# Swift8ComicSDK

[![CI Status](http://img.shields.io/travis/RayTW/Swift8ComicSDK.svg?style=flat)](https://travis-ci.org/RayTW/Swift8ComicSDK)
[![Version](https://img.shields.io/cocoapods/v/Swift8ComicSDK.svg?style=flat)](http://cocoapods.org/pods/Swift8ComicSDK)
[![License](https://img.shields.io/cocoapods/l/Swift8ComicSDK.svg?style=flat)](http://cocoapods.org/pods/Swift8ComicSDK)
[![Platform](https://img.shields.io/cocoapods/p/Swift8ComicSDK.svg?style=flat)](http://cocoapods.org/pods/Swift8ComicSDK)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

### Class R8Comic, for example
```
 //讀取漫畫存放的伺服器host
        R8Comic.get().loadSiteUrlList { (hostMap : [String : String]) in
            self.mHostMap = hostMap
            
            //取得全部漫畫
            R8Comic.get().getAll { (comics:[Comic]) in
                self.mComics = comics
                let comic = comics[comics.count - 1]
                
                print("comic,id==>\(comic.getId()), name[\(comic.getName())]")
                print("comic,封面大圖==>\(comic.getIconUrl()), 封面小圖[\(comic.getSmallIconUrl())]")
                
                //單1本漫畫，解析說明、集數等等資料…
                R8Comic.get().loadComicDetail(comic, onLoadDetail: { (comic) in
                    
                    
                    print("comic,集數==>\(comic.getEpisode().count)")
                    //單集漫畫讀取圖片網址資料
                    let episode = comic.getEpisode()[0]
                    episode.setUrl(hostMap[episode.getCatid()]! + episode.getUrl())
                    
                    print("comic,episode名稱==>\(episode.getName())")
                    print("comic,episode,ch==>\(episode.getCh())")
                    print("comic,episode,url==>\(episode.getUrl())")
                    
                    
                    R8Comic.get().loadEpisodeDetail(episode, onLoadDetail: { (episode) in
                        print("episode,getChs=>\(episode.getChs())")
                        
                        episode.setUpPages()
                        
                        print("episode,單集多張圖片網址=>\(episode.getImageUrlList())")
                        
                    })
                })
            }
```

## Requirements

Add trusted comic site in info.plist
```
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

## Author

RayTW, ray00000sina@gmail.com

## License

Swift8ComicSDK is available under the MIT license. See the LICENSE file for more info.
