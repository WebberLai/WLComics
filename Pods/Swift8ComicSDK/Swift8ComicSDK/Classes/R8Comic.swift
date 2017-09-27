open class R8Comic{
    private static let sInstance : R8Comic = R8Comic()
    private var mConfig : Config = Config()
    private let mParser : Parser = Parser()
    
    init() {
        
    }
    
    open class func get() -> R8Comic{
        return sInstance
    }
    
    func setConfig(_ config: Config){
        mConfig = config
    }
    
    /**
     * 讀取全部漫畫編號、名稱
     **/
    open func getAll(_ comics: @escaping ([Comic]) -> Void) -> Void {
        let url = URL(string: mConfig.mAllUrl)
        let request = URLRequest(url: url!)
        let session = URLSession(configuration: URLSessionConfiguration.default)
        
        let task = session.dataTask(with: request, completionHandler: {(data, response, error) -> Void in
            if let data = data {
                
                let string = StringUtility.dataToStringBig5(data: data)
                let comicAry = self.mParser.allComics(string, self.mConfig)
                
                if let response = response as? HTTPURLResponse , 200...299 ~= response.statusCode {
                    comics(comicAry)
                } else {
                    print("getAll fail")
                }
            }
        })
        task.resume()
    }
    
    /**
     * 讀取漫畫簡介、作者、最後更新日期、集數列表
     **/
    open func loadComicDetail(_ comic: Comic, onLoadDetail: @escaping (Comic) -> Void) -> Void{
        let url = URL(string: mConfig.getComicDetailUrl(comic.getId()))
        let request = URLRequest(url: url!)
        let session = URLSession(configuration: URLSessionConfiguration.default)
        
        let task = session.dataTask(with: request, completionHandler: {(data, response, error) -> Void in
            if let data = data {
                
                let string = StringUtility.dataToStringBig5(data: data)
                
                let comicDetail = self.mParser.comicDetail(htmlString: string, comic: comic)
                
                if let response = response as? HTTPURLResponse , 200...299 ~= response.statusCode {
                   onLoadDetail(comicDetail)
                } else {
                    print("loadComicDetail fail")
                }
            }
        })
        task.resume()
    }
    
    /**
     * 讀取漫畫簡介、作者、最後更新日期、集數列表
     **/
    open func loadEpisodeDetail(_ episode: Episode, onLoadDetail: @escaping (Episode) -> Void) -> Void{
        let url = URL(string: episode.getUrl()) //wrok around
        let request = URLRequest(url: url!)
        let session = URLSession(configuration: URLSessionConfiguration.default)
        
        let task = session.dataTask(with: request, completionHandler: {(data, response, error) -> Void in
            if let data = data {
                
                let string = StringUtility.dataToStringBig5(data: data)
                
                let detail = self.mParser.episodeDetail(string, episode: episode)
                
                if let response = response as? HTTPURLResponse , 200...299 ~= response.statusCode {
                    onLoadDetail(detail)
                } else {
                    print("loadComicDetail fail")
                }
            }
        })
        task.resume()
    }

    
    /**
     * 讀取漫畫圖片實際存放的Server site網址列表
     **/
    open func loadSiteUrlList(_ onLoadList: @escaping ([String : String]) -> Void) -> Void{
        let url = URL(string: mConfig.mCviewJSUrl)
        let request = URLRequest(url: url!)
        let session = URLSession(configuration: URLSessionConfiguration.default)
        
        let task = session.dataTask(with: request, completionHandler: {(data, response, error) -> Void in
            if let data = data {
                
                let string = StringUtility.dataToStringBig5(data: data)
                
                let comicDetail = self.mParser.cviewJS(string)
                
                if let response = response as? HTTPURLResponse , 200...299 ~= response.statusCode {
                    onLoadList(comicDetail)
                } else {
                    print("loadSiteUrlList fail")
                }
            }
        })
        task.resume()
    }
    
    /**
     * 搜尋漫畫，搜尋到的漫畫僅有id、name，不包含漫畫簡介、集數等等資訊
     *
     * @param keyword
     *            搜尋漫畫的關鍵字，比如"海賊王"
     *
     */
    open func searchComic(_ keyword : String, onLoadList: @escaping ([Comic]) -> Void) -> Void{
        DispatchQueue.global(qos: .userInitiated).async {
            var comics : [Comic] = [Comic]()
            let url = URL(string: self.mConfig.getSearchUrl(keyword, 1))
            
            let request = URLRequest(url: url!)
            let session = URLSession(configuration: URLSessionConfiguration.default)
            let downloadGroup = DispatchGroup()
            downloadGroup.enter()
            
            let task = session.dataTask(with: request, completionHandler: {(data, response, error) -> Void in
                if let data = data {
                    let htmlString = StringUtility.dataToStringBig5(data: data)
                    let maxPage = self.mParser.searchComic(htmlString, onLoadComics: { (list : [Comic]) in
                        comics += list
                    }, self.mConfig)
                    
                    if let response = response as? HTTPURLResponse , 200...299 ~= response.statusCode {
                        if(maxPage > 1){
                            
                            for i in 2..<maxPage {
                                let url2 = URL(string: self.mConfig.getSearchUrl(keyword, i))
                                
                                let request = URLRequest(url: url2!)
                                let session = URLSession(configuration: URLSessionConfiguration.default)
                                
                                downloadGroup.enter()
                                
                                let task = session.dataTask(with: request, completionHandler: {(data, response, error) -> Void in
                                    if let data = data {
                                        
                                        let htmlString = StringUtility.dataToStringBig5(data: data)
                                        //用'_'接收回傳值可不處理，以消除編譯的警告訊息
                                        _ = self.mParser.searchComic(htmlString, onLoadComics: { (list : [Comic]) in
                                            comics += list
                                        }, self.mConfig)
                                        
                                        if let response = response as? HTTPURLResponse , 200...299 ~= response.statusCode {
                                            //not thing
                                        } else {
                                            print("searchComic,page=\(i) fail")
                                        }
                                    }
                                    downloadGroup.leave()
                                })
                                task.resume()
                            }
                        }
                    } else {
                        print("searchComic fail")
                    }
                    downloadGroup.leave()
                }
            })
            task.resume()
            
            //停留等待全部查詢漫畫的分頁結果解析完成後，再將往下執行
            downloadGroup.wait()
            
            onLoadList(comics)
        }
    }
    
    /**
     * 快速搜尋漫畫名稱
     *
     * @param keyword
     *            搜尋漫畫的關鍵字，比如"海賊王"
     * @param listener
     **/
    open func quickSearchComic(_ keyword : String, onLoadList: @escaping ([String]) -> Void) -> Void{
        let url = URL(string: mConfig.getQuickSearchUrl(keyword))
        
        let request = URLRequest(url: url!)
        let session = URLSession(configuration: URLSessionConfiguration.default)
        
        let task = session.dataTask(with: request, completionHandler: {(data, response, error) -> Void in
            if let data = data {
                
                let htmlString = StringUtility.dataToStringGB2312(data: data)
                let comicList = self.mParser.quickSearchComic(htmlString)
                
                if let response = response as? HTTPURLResponse , 200...299 ~= response.statusCode {
                    onLoadList(comicList)
                } else {
                    print("quickSearchComic fail")
                }
            }
        })
        task.resume()
    }
    
    /*
     * 取得指定漫畫封面大圖
     */
    open func getComicIconUrl(_ comicId: String) -> String{
        return self.mConfig.getComicIconUrl(comicId)
    }
    
    /*
     * 取得指定漫畫封面小圖
     */
    open func getComicSmallIconUrl(_ comicId: String) -> String{
        return self.mConfig.getComicSmallIconUrl(comicId)
    }
    
    open func getParser() -> Parser{
        return self.mParser;
    }
    
    open func getConfig() -> Config{
        return self.mConfig;
    }
    
    open func generatorFakeComic(_ id : String, name : String) -> Comic{
        let comic = Comic()
        comic.setId(id)
        comic.setName(name)
        return comic
    }
    
    open func generatorFakeEpisode(_ url : String) -> Episode{
        let episode = Episode()
        episode.setUrl(url)
        
        return episode
    }
}
