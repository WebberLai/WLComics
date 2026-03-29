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
        guard let url = URL(string: mConfig.mAllUrl) else {
            print("getAll: invalid URL")
            return
        }
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  200...299 ~= response.statusCode else {
                print("getAll fail: \(error?.localizedDescription ?? "unknown")")
                return
            }
            let string = StringUtility.dataToStringBig5(data: data)
            let comicAry = self.mParser.allComics(string, self.mConfig)
            comics(comicAry)
        }
        task.resume()
    }

    /**
     * 讀取漫畫簡介、作者、最後更新日期、集數列表
     **/
    open func loadComicDetail(_ comic: Comic, onLoadDetail: @escaping (Comic) -> Void) -> Void{
        guard let url = URL(string: mConfig.getComicDetailUrl(comic.getId())) else {
            print("loadComicDetail: invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        let session = URLSession(configuration: .default)

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  200...299 ~= response.statusCode else {
                print("loadComicDetail fail: \(error?.localizedDescription ?? "unknown")")
                return
            }
            let string = StringUtility.dataToStringBig5(data: data)
            let comicDetail = self.mParser.comicDetail(htmlString: string, comic: comic)
            onLoadDetail(comicDetail)
        }
        task.resume()
    }

    /**
     * 讀取漫畫圖片下載網址
     **/
    open func loadEpisodeDetail(_ episode: Episode, onLoadDetail: @escaping (Episode) -> Void) -> Void{
        guard let url = URL(string: episode.getUrl()) else {
            print("loadEpisodeDetail: invalid URL - \(episode.getUrl())")
            return
        }
        var request = URLRequest(url: url)
        request.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        let session = URLSession(configuration: .default)

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  200...299 ~= response.statusCode else {
                print("loadEpisodeDetail fail: \(error?.localizedDescription ?? "unknown")")
                return
            }
            let string = StringUtility.dataToStringBig5(data: data)
            print("loadEpisodeDetail: URL=\(url), dataSize=\(data.count), htmlLength=\(string.count)")
            if string.count < 500 {
                print("loadEpisodeDetail: SHORT HTML=\(string)")
            } else {
                print("loadEpisodeDetail: first 500 chars=\(String(string.prefix(500)))")
            }
            let detail = self.mParser.episodeDetail(string, episode: episode)
            onLoadDetail(detail)
        }
        task.resume()
    }

    /**
     * 讀取漫畫圖片實際存放的Server site網址列表
     **/
    open func loadSiteUrlList(_ onLoadList: @escaping ([String : String]) -> Void) -> Void{
        guard let url = URL(string: mConfig.mCviewJSUrl) else {
            print("loadSiteUrlList: invalid URL")
            return
        }
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  200...299 ~= response.statusCode else {
                print("loadSiteUrlList fail: \(error?.localizedDescription ?? "unknown")")
                return
            }
            let string = StringUtility.dataToStringBig5(data: data)
            let cviewMap = self.mParser.cviewJS(string)
            onLoadList(cviewMap)
        }
        task.resume()
    }

    /**
     * 搜尋漫畫
     */
    open func searchComic(_ keyword : String, onLoadList: @escaping ([Comic]) -> Void) -> Void{
        DispatchQueue.global(qos: .userInitiated).async {
            var comics : [Comic] = [Comic]()
            guard let url = URL(string: self.mConfig.getSearchUrl(keyword, 1)) else {
                onLoadList(comics)
                return
            }

            let request = URLRequest(url: url)
            let session = URLSession(configuration: .default)
            let downloadGroup = DispatchGroup()
            downloadGroup.enter()

            let task = session.dataTask(with: request) { data, response, error in
                defer { downloadGroup.leave() }
                guard let data = data,
                      let response = response as? HTTPURLResponse,
                      200...299 ~= response.statusCode else {
                    print("searchComic fail")
                    return
                }
                let htmlString = StringUtility.dataToStringBig5(data: data)
                let maxPage = self.mParser.searchComic(htmlString, onLoadComics: { list in
                    comics += list
                }, self.mConfig)

                if maxPage > 1 {
                    for i in 2...maxPage {
                        guard let url2 = URL(string: self.mConfig.getSearchUrl(keyword, i)) else { continue }
                        let request2 = URLRequest(url: url2)
                        downloadGroup.enter()

                        let task2 = session.dataTask(with: request2) { data, response, error in
                            defer { downloadGroup.leave() }
                            guard let data = data,
                                  let response = response as? HTTPURLResponse,
                                  200...299 ~= response.statusCode else { return }
                            let htmlString = StringUtility.dataToStringBig5(data: data)
                            _ = self.mParser.searchComic(htmlString, onLoadComics: { list in
                                comics += list
                            }, self.mConfig)
                        }
                        task2.resume()
                    }
                }
            }
            task.resume()
            downloadGroup.wait()
            onLoadList(comics)
        }
    }

    /**
     * 快速搜尋漫畫名稱
     **/
    open func quickSearchComic(_ keyword : String, onLoadList: @escaping ([String]) -> Void) -> Void{
        guard let url = URL(string: mConfig.getQuickSearchUrl(keyword)) else { return }
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  200...299 ~= response.statusCode else {
                print("quickSearchComic fail")
                return
            }
            let htmlString = StringUtility.dataToStringGB2312(data: data)
            let comicList = self.mParser.quickSearchComic(htmlString)
            onLoadList(comicList)
        }
        task.resume()
    }

    open func getComicIconUrl(_ comicId: String) -> String{
        return self.mConfig.getComicIconUrl(comicId)
    }

    open func getComicSmallIconUrl(_ comicId: String) -> String{
        return self.mConfig.getComicSmallIconUrl(comicId)
    }

    open func getParser() -> Parser{
        return self.mParser
    }

    open func getConfig() -> Config{
        return self.mConfig
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
