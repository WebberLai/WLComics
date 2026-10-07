//
//  UpdateChecker.swift
//  WLComics
//

import Foundation

/// 向網站抓收藏漫畫的集數列表，交給 UpdateTracker 比對。只在 main thread 呼叫。
class UpdateChecker {

    enum Reason {
        case foreground
        case background
        /// 下拉重新整理，不受 24 小時限制
        case manual
    }

    struct Update {
        let comicId: String
        let comicName: String
        /// 這次檢查抓到的最新一集名稱；這次沒抓到（之前留下的未通知更新）時為 nil
        let latestEpisodeName: String?
    }

    struct Result {
        /// 有新集數且還沒通知過的收藏
        let updates: [Update]
        let failedCount: Int
        /// 因 24 小時節流而沒有實際檢查
        let skipped: Bool
    }

    static let shared = UpdateChecker()

    private static let minimumInterval: TimeInterval = 24 * 60 * 60
    /// SDK 失敗時不會回呼，自己設 timeout
    private static let requestTimeout: TimeInterval = 20
    /// 一次最多同時抓 2 部，避免對網站造成負擔
    private static let maxConcurrent = 2

    private var completions = [(Result) -> Void]()
    private var isRunning = false
    private var isCancelled = false
    private var favorites = [(id: String, name: String)]()
    private var queue = [(id: String, name: String)]()
    private var inFlight = 0
    private var succeeded = 0
    private var failed = 0
    private var latestEpisodeNames = [String: String]()
    /// 每輪檢查遞增，上一輪遲到的回呼不會影響這一輪
    private var generation = 0

    func check(reason: Reason, completion: @escaping (Result) -> Void) {
        completions.append(completion)
        // 已有檢查在跑：併入同一輪，不重複發請求
        guard !isRunning else { return }

        // 背景任務是在上一輪「開始」時排程 24 小時後，而上次檢查時間在一輪「結束」時才寫入，
        // 留一小時寬限，避免背景這輪剛好被自己的節流擋掉
        let interval = reason == .background ? UpdateChecker.minimumInterval - 60 * 60 : UpdateChecker.minimumInterval
        if reason != .manual, let last = UpdateTracker.lastFullCheckAt,
           Date().timeIntervalSince(last) < interval {
            finish(skipped: true)
            return
        }

        favorites = UpdateChecker.favoriteList()
        queue = favorites
        isRunning = true
        isCancelled = false
        inFlight = 0
        succeeded = 0
        failed = 0
        latestEpisodeNames = [:]
        generation += 1
        launchNext()
    }

    /// 背景任務被系統中止時呼叫：不再發新請求，立刻以目前結果結束
    func cancel() {
        guard isRunning else { return }
        isCancelled = true
        queue.removeAll()
        finish(skipped: false)
    }

    private func launchNext() {
        while inFlight < UpdateChecker.maxConcurrent, !queue.isEmpty {
            let item = queue.removeFirst()
            inFlight += 1
            fetch(item)
        }
        if inFlight == 0 && queue.isEmpty {
            finish(skipped: false)
        }
    }

    private func fetch(_ item: (id: String, name: String)) {
        let round = generation
        var handled = false
        // 正常回呼與 timeout 誰先到就用誰，另一個忽略
        let handle: (Comic?) -> Void = { comic in
            DispatchQueue.main.async {
                guard !handled, round == self.generation, self.isRunning else { return }
                handled = true
                self.inFlight -= 1
                let episodes = comic?.getEpisode() ?? []
                if episodes.isEmpty {
                    // 逾時、網路錯誤，或解析出 0 集（多半是網站改版），都當失敗，不動資料
                    self.failed += 1
                } else {
                    self.succeeded += 1
                    UpdateTracker.recordCheck(comicId: item.id, episodeCount: episodes.count)
                    // 集數依網頁順序由舊到新，最後一集是最新的
                    self.latestEpisodeNames[item.id] = episodes.last?.getName()
                }
                self.launchNext()
            }
        }
        let r8comic = WLComics.sharedInstance().getR8Comic()
        r8comic.loadComicDetail(r8comic.generatorFakeComic(item.id, name: item.name)) { comic in
            handle(comic)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + UpdateChecker.requestTimeout) {
            handle(nil)
        }
    }

    private func finish(skipped: Bool) {
        if skipped {
            // 沒有實際檢查，上一輪的集名可能已過時，通知改用「有新集數」
            latestEpisodeNames = [:]
        } else {
            // 全部失敗（例如沒網路）時不記時間，下次回到前景會再試
            if succeeded > 0 {
                UpdateTracker.lastFullCheckAt = Date()
            }
            if !isCancelled {
                UpdateTracker.prune(keeping: Set(favorites.map { $0.id }))
            }
        }

        let names = Dictionary(UpdateChecker.favoriteList().map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        let updates = UpdateTracker.pendingNotificationIds().map { id in
            Update(comicId: id, comicName: names[id] ?? "", latestEpisodeName: latestEpisodeNames[id])
        }
        let result = Result(updates: updates, failedCount: skipped ? 0 : failed, skipped: skipped)

        isRunning = false
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(result) }
    }

    private static func favoriteList() -> [(id: String, name: String)] {
        return FavoriteComics.listAllFavorite().compactMap { dict in
            guard let id = dict.object(forKey: "comic_id") as? String,
                  let name = dict.object(forKey: "name") as? String else { return nil }
            return (id: id, name: name)
        }
    }
}
