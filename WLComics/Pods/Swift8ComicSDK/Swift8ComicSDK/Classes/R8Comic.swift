open class R8Comic{
    fileprivate static let sInstance : R8Comic = R8Comic()
    fileprivate var mConfig : Config = Config()
    fileprivate let mParser : Parser = Parser()
    
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
