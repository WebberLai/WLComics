//
//  DownloadManager.swift
//  WLComics
//

import UIKit
import BackgroundTasks
import os

/// 離線閱讀的下載管理。
/// 圖片存在 Application Support/Downloads/<漫畫id>/<集數資料夾>/001.jpg…，
/// 每部漫畫一份 manifest.json 記錄漫畫與各集資訊。只能手動刪除，不會自動清除。
final class DownloadManager {

    static let shared = DownloadManager()

    /// 診斷用。不接偵錯器時可在 Mac 的「主控台」App 選擇裝置，以子系統 <bundle id>、類別 Download 過濾
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WLComics", category: "Download")

    /// 下載狀態或進度改變時發出（main thread），userInfo["comicId"] 是變動的漫畫
    static let didChangeNotification = Notification.Name("DownloadManagerDidChange")

    enum State: Equatable {
        case none
        case queued
        case downloading(Double)   // 0...1
        case downloaded
        case incomplete            // 下載過但沒完成（失敗或中斷），再按一次下載會續傳
    }

    struct EpisodeRecord: Codable {
        var key: String            // 正規化後的集數網址，用來比對
        var url: String            // 原始網址，離線時還原 Episode 用
        var name: String
        var order: Int             // 在網站集數列表中的位置，離線列表照這個排序
        var folder: String
        var pageFiles: [String]    // 依頁序排列的檔名
        var completed: Bool
    }

    struct ComicRecord: Codable {
        var comicId: String
        var name: String
        var episodes: [EpisodeRecord]
        var updatedAt: TimeInterval
    }

    private struct Job {
        let comicId: String
        let comicName: String
        let episodeName: String
        let episodeUrl: String
        let order: Int
        let key: String
        var id: String { return DownloadManager.jobId(comicId, key) }
    }

    // 以下狀態一律在 stateQueue 上讀寫
    private let stateQueue = DispatchQueue(label: "DownloadManager.state")
    private var records = [String: ComicRecord]()
    private var pending = [Job]()
    private var activeJob: Job?
    private var activeProgress: Double = 0
    private var cancelledIds = Set<String>()
    private var lastProgressPost = Date.distantPast

    // iOS 26 起用 BGContinuedProcessingTask 讓佇列在 App 切到背景後繼續下載，系統會顯示進度。
    // 「一批」是指從佇列開始有工作，到整個佇列清空為止的所有集數
    private var continuedTask: AnyObject?      // BGContinuedProcessingTask，型別受限於 iOS 26 所以存成 AnyObject
    private var continuedTaskRequested = false
    private var batchTotal = 0
    private var batchDone = 0
    /// 背景工作被系統收回（例如螢幕鎖定）後暫停佇列，不開始下一集；回到前景時自動繼續
    private var paused = false

    /// 需和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers（<bundle id>.download.*）一致
    private static let continuedTaskPrefix = (Bundle.main.bundleIdentifier ?? "com.webberlai.WLComics") + ".download."

    private let workQueue = DispatchQueue(label: "DownloadManager.work", qos: .utility)
    private let session: URLSession
    private let rootURL: URL
    private let fileManager = FileManager.default

    /// 放慢下載節奏，避免短時間大量請求被網站當成爬蟲封鎖：
    /// 一次只抓一頁，頁與頁之間、集與集之間都隨機停頓
    private static let concurrentPages = 1
    private static let pageDelay: ClosedRange<Double> = 1.5...3.5
    private static let episodeDelay: ClosedRange<Double> = 6...12
    private static let pageRetryCount = 3
    private static let retryDelay: TimeInterval = 5

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = DownloadManager.concurrentPages
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var root = support.appendingPathComponent("Downloads", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        // 下載的漫畫可以重新下載，不佔用使用者的 iCloud 備份空間（設定在資料夾上，底下內容一併排除）
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        rootURL = root

        loadAllRecords()

        // 單例不會被釋放，不需要移除觀察者
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.stateQueue.async { self?.resumeIfPausedLocked() }
        }
    }

    // MARK: - 查詢

    func state(comicId: String, episodeUrl: String) -> State {
        let key = ReadingProgress.normalizedEpisodeUrl(episodeUrl)
        let id = DownloadManager.jobId(comicId, key)
        return stateQueue.sync {
            if activeJob?.id == id { return .downloading(activeProgress) }
            if pending.contains(where: { $0.id == id }) { return .queued }
            guard let episode = records[comicId]?.episodes.first(where: { $0.key == key }) else { return .none }
            return episode.completed ? .downloaded : .incomplete
        }
    }

    /// 已下載完成的那一集，依頁序回傳本機檔案位置；未完成或沒下載回傳 nil
    func localPageURLs(comicId: String, episodeUrl: String) -> [URL]? {
        let key = ReadingProgress.normalizedEpisodeUrl(episodeUrl)
        guard let episode = stateQueue.sync(execute: { records[comicId]?.episodes.first { $0.key == key } }),
              episode.completed else { return nil }
        let folder = episodeFolderURL(comicId: comicId, folder: episode.folder)
        return episode.pageFiles.map { folder.appendingPathComponent($0) }
    }

    /// 有下載內容（含未完成）的漫畫，最近下載的在前
    func downloadedComics() -> [ComicRecord] {
        return stateQueue.sync {
            records.values.filter { !$0.episodes.isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func isDownloading(comicId: String) -> Bool {
        return stateQueue.sync {
            activeJob?.comicId == comicId || pending.contains { $0.comicId == comicId }
        }
    }

    /// 離線時從下載紀錄還原已完成的集數，順序與網站列表相同
    func downloadedEpisodes(comicId: String) -> [Episode] {
        let episodes = stateQueue.sync { records[comicId]?.episodes ?? [] }
        return episodes.filter { $0.completed }.sorted { $0.order < $1.order }.map { record in
            DownloadManager.makeEpisode(name: record.name, url: record.url)
        }
    }

    /// 重建 Episode。網站的集數網址是「<漫畫id>.html?ch=<集數>」，
    /// JSnview 解析圖片網址需要 ch（原本由 SDK 解析漫畫頁時設定），所以要從網址取出補上
    private static func makeEpisode(name: String, url: String) -> Episode {
        let episode = Episode()
        episode.setName(name)
        episode.setUrl(url)
        if let range = url.range(of: "ch=") {
            let ch = url[range.upperBound...].prefix { "0123456789".contains($0) }
            if !ch.isEmpty { episode.setCh(String(ch)) }
        }
        return episode
    }

    /// 下載時一併存下的封面
    func coverURL(comicId: String) -> URL? {
        let url = comicFolderURL(comicId).appendingPathComponent("cover.jpg")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// 這部漫畫佔用的空間（bytes），會掃描檔案，請在背景呼叫
    func diskUsage(comicId: String) -> Int64 {
        let folder = comicFolderURL(comicId)
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - 下載

    /// 加入下載佇列；已下載完成或已在佇列中的會略過。order 是該集在網站列表中的位置
    func download(comic: Comic, episodes: [(episode: Episode, order: Int)]) {
        let comicId = comic.getId()
        let comicName = comic.getName()
        stateQueue.async {
            var added = 0
            for item in episodes {
                let key = ReadingProgress.normalizedEpisodeUrl(item.episode.getUrl())
                let job = Job(comicId: comicId, comicName: comicName, episodeName: item.episode.getName(),
                              episodeUrl: item.episode.getUrl(), order: item.order, key: key)
                if self.activeJob?.id == job.id || self.pending.contains(where: { $0.id == job.id }) { continue }
                if self.records[comicId]?.episodes.first(where: { $0.key == key })?.completed == true { continue }
                self.cancelledIds.remove(job.id)
                self.pending.append(job)
                added += 1
            }
            if self.paused {
                // 暫停中又按下載：連同暫停的佇列一起重新開始
                self.resumeIfPausedLocked()
            } else if added > 0 {
                self.batchTotal += added
                self.updateContinuedProgressLocked()
                self.requestContinuedTaskIfNeededLocked(comicName: comicName)
            }
            self.postChange(comicId: comicId)
            self.startNextIfNeeded()
        }
    }

    // MARK: - 刪除（只有手動刪除）

    /// 刪除單集；若正在下載或排隊中會一併取消
    func deleteEpisode(comicId: String, episodeUrl: String) {
        let key = ReadingProgress.normalizedEpisodeUrl(episodeUrl)
        let id = DownloadManager.jobId(comicId, key)
        stateQueue.async {
            self.removePendingLocked { $0.id == id }
            if self.activeJob?.id == id { self.cancelledIds.insert(id) }
            guard var record = self.records[comicId] else {
                self.postChange(comicId: comicId)
                return
            }
            if let episode = record.episodes.first(where: { $0.key == key }) {
                try? self.fileManager.removeItem(at: self.episodeFolderURL(comicId: comicId, folder: episode.folder))
            }
            record.episodes.removeAll { $0.key == key }
            if record.episodes.isEmpty {
                self.removeComicLocked(comicId)
            } else {
                self.records[comicId] = record
                self.saveRecordLocked(record)
            }
            self.postChange(comicId: comicId)
        }
    }

    /// 刪除整部漫畫的下載；排隊中與下載中的也會取消
    func deleteComic(comicId: String) {
        stateQueue.async {
            self.removePendingLocked { $0.comicId == comicId }
            if let active = self.activeJob, active.comicId == comicId { self.cancelledIds.insert(active.id) }
            self.removeComicLocked(comicId)
            self.postChange(comicId: comicId)
        }
    }

    // MARK: - 下載流程

    private func startNextIfNeeded() {
        guard activeJob == nil, !paused else { return }
        guard !pending.isEmpty else {
            finishContinuedTaskLocked(success: true)
            return
        }
        let job = pending.removeFirst()
        activeJob = job
        activeProgress = 0
        updateContinuedProgressLocked()
        updateContinuedTitleLocked(job: job)
        workQueue.async { self.run(job) }
    }

    /// 從佇列移除排隊中的集數，並從這一批的總數扣掉；佇列因此清空時結束背景工作。呼叫前必須已在 stateQueue 上
    private func removePendingLocked(where shouldRemove: (Job) -> Bool) {
        let before = pending.count
        pending.removeAll(where: shouldRemove)
        batchTotal = max(batchDone, batchTotal - (before - pending.count))
        if activeJob == nil && pending.isEmpty {
            paused = false
            finishContinuedTaskLocked(success: true)
        } else {
            updateContinuedProgressLocked()
        }
    }

    private func run(_ job: Job) {
        // 切到背景時多爭取一點時間把這一集下載完。已經有 BGContinuedProcessingTask 撐住整個佇列時就不需要，
        // 否則這個只有約 30 秒的背景工作會一直掛著，系統會警告並可能因此終止 App
        var taskId = UIBackgroundTaskIdentifier.invalid
        if stateQueue.sync(execute: { continuedTask == nil }) {
            DispatchQueue.main.sync {
                taskId = UIApplication.shared.beginBackgroundTask(withName: "DownloadEpisode") {
                    UIApplication.shared.endBackgroundTask(taskId)
                    taskId = .invalid
                }
            }
        }

        performDownload(job)

        // 先結束這一集，畫面才會馬上顯示「已下載」，不會在休息期間卡在「下載中」
        let hasMore: Bool = stateQueue.sync {
            activeJob = nil
            cancelledIds.remove(job.id)
            batchDone = min(batchDone + 1, batchTotal)
            updateContinuedProgressLocked()
            postChange(comicId: job.comicId)
            return !pending.isEmpty
        }
        // 還有下一集要下載時先休息一下再繼續
        if hasMore {
            Thread.sleep(forTimeInterval: Double.random(in: DownloadManager.episodeDelay))
        }
        stateQueue.async { self.startNextIfNeeded() }
        DispatchQueue.main.async {
            if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
        }
    }

    private func isCancelled(_ job: Job) -> Bool {
        return stateQueue.sync { cancelledIds.contains(job.id) }
    }

    private func performDownload(_ job: Job) {
        downloadCoverIfNeeded(comicId: job.comicId)

        // 1. 取得這一集所有圖片網址。用新的 Episode 物件，避免和閱讀器同時操作同一個物件
        let episode = DownloadManager.makeEpisode(name: job.episodeName, url: job.episodeUrl)
        let semaphore = DispatchSemaphore(value: 0)
        var pages = [String]()
        var referer = job.episodeUrl
        WLComics.sharedInstance().loadEpisodeDetail(episode) { detail in
            detail.setUpPages()
            pages = detail.getImageUrlList()
            referer = detail.getUrl()
            semaphore.signal()
        }
        // 網站回應失敗時 SDK 不會呼叫 callback，用逾時結束
        // 還沒拿到頁面就失敗時不留新紀錄；先前若有未完成的紀錄則保留，之後可續傳
        guard semaphore.wait(timeout: .now() + 30) == .success, !pages.isEmpty, !isCancelled(job) else {
            DownloadManager.log.error("解析圖片網址失敗或已取消：\(job.episodeName, privacy: .public)，頁數 \(pages.count)")
            cleanUpIfCancelled(job)
            return
        }

        // 2. 先寫入紀錄（未完成），中斷後也知道有這一集、可以續傳
        let folder = DownloadManager.folderName(for: job.key)
        let pageFiles = pages.enumerated().map { index, page -> String in
            let ext = URL(string: page)?.pathExtension.lowercased() ?? ""
            let safeExt = ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) ? ext : "jpg"
            return String(format: "%03d.%@", index + 1, safeExt)
        }
        let folderURL = episodeFolderURL(comicId: job.comicId, folder: folder)
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        updateRecord(job: job, folder: folder, pageFiles: pageFiles, completed: false)

        // 3. 下載每一頁，已存在的檔案略過（續傳）
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = DownloadManager.concurrentPages
        let lock = NSLock()
        var finished = 0
        var failed = false
        for (index, page) in pages.enumerated() {
            let destination = folderURL.appendingPathComponent(pageFiles[index])
            queue.addOperation {
                guard !self.isCancelled(job) else { return }
                var ok = self.fileExists(destination)
                if !ok {
                    ok = self.downloadFile(from: page, referer: referer, to: destination)
                    // 只有真的發出請求才停頓，續傳時已存在的頁面直接略過
                    Thread.sleep(forTimeInterval: Double.random(in: DownloadManager.pageDelay))
                }
                lock.lock()
                finished += 1
                if !ok { failed = true }
                let done = finished
                lock.unlock()
                self.reportProgress(page: done, of: pages.count, job: job)
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        // 4. 全部頁面都在才算完成；被取消的話不寫回紀錄，並清掉下載途中又建立的資料夾
        guard !isCancelled(job) else {
            cleanUpIfCancelled(job)
            return
        }
        let allPresent = !failed && pageFiles.allSatisfy { fileExists(folderURL.appendingPathComponent($0)) }
        updateRecord(job: job, folder: folder, pageFiles: pageFiles, completed: allPresent)
        DownloadManager.log.notice("集數結束：\(job.episodeName, privacy: .public) 完成 \(allPresent) 有失敗頁 \(failed)")
    }

    /// 同步下載單一檔案，失敗時重試
    private func downloadFile(from urlString: String, referer: String, to destination: URL) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        // 8comic 沒有正確的 Referer 會拒絕圖片請求
        request.setValue(referer, forHTTPHeaderField: "Referer")

        for attempt in 0..<DownloadManager.pageRetryCount {
            if attempt > 0 { Thread.sleep(forTimeInterval: DownloadManager.retryDelay) }
            let semaphore = DispatchSemaphore(value: 0)
            var success = false
            session.downloadTask(with: request) { tempURL, response, error in
                defer { semaphore.signal() }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard let tempURL = tempURL, (200..<300).contains(status) else {
                    DownloadManager.log.error("下載失敗（第 \(attempt + 1) 次）狀態碼 \(status) 錯誤 \(String(describing: error), privacy: .public) 檔案 \(destination.lastPathComponent, privacy: .public)")
                    return
                }
                try? self.fileManager.removeItem(at: destination)
                do {
                    try self.fileManager.moveItem(at: tempURL, to: destination)
                    success = true
                } catch {
                    // 螢幕鎖定時若檔案保護不允許寫入，會在這裡失敗
                    DownloadManager.log.error("存檔失敗：\(error.localizedDescription, privacy: .public) 檔案 \(destination.lastPathComponent, privacy: .public)")
                }
            }.resume()
            semaphore.wait()
            if success { return true }
        }
        return false
    }

    private func downloadCoverIfNeeded(comicId: String) {
        let destination = comicFolderURL(comicId).appendingPathComponent("cover.jpg")
        guard !fileExists(destination) else { return }
        try? fileManager.createDirectory(at: comicFolderURL(comicId), withIntermediateDirectories: true)
        let coverUrl = WLComics.sharedInstance().getR8Comic().getComicSmallIconUrl(comicId)
        _ = downloadFile(from: coverUrl, referer: "https://www.8comic.com/", to: destination)
    }

    private func reportProgress(page: Int, of pageCount: Int, job: Job) {
        let progress = Double(page) / Double(pageCount)
        stateQueue.async {
            guard self.activeJob?.id == job.id else { return }
            self.activeProgress = progress
            self.updateContinuedProgressLocked()
            self.updateContinuedTitleLocked(job: job, page: page, pageCount: pageCount)
            // 進度通知節流，避免列表每張圖都重新整理
            guard Date().timeIntervalSince(self.lastProgressPost) > 0.3 || progress >= 1 else { return }
            self.lastProgressPost = Date()
            self.postChange(comicId: job.comicId)
        }
    }

    /// 刪除和下載同時進行時，下載流程可能在刪除後又建立資料夾，這裡補刪
    private func cleanUpIfCancelled(_ job: Job) {
        stateQueue.sync {
            guard cancelledIds.contains(job.id) else { return }
            if let record = records[job.comicId] {
                if !record.episodes.contains(where: { $0.key == job.key }) {
                    try? fileManager.removeItem(at: episodeFolderURL(comicId: job.comicId,
                                                                    folder: DownloadManager.folderName(for: job.key)))
                }
            } else {
                try? fileManager.removeItem(at: comicFolderURL(job.comicId))
            }
        }
    }

    // MARK: - 背景繼續下載（iOS 26+）

    /// 這一批還沒有背景工作時向系統申請。必須在 App 位於前景時提交，下載都是使用者按的所以沒問題。
    /// 呼叫前必須已在 stateQueue 上
    private func requestContinuedTaskIfNeededLocked(comicName: String) {
        guard #available(iOS 26.0, *) else { return }
        // Mac 上不會被暫停，也不支援這個 API
        guard !ProcessInfo.processInfo.isiOSAppOnMac, continuedTask == nil, !continuedTaskRequested else { return }
        continuedTaskRequested = true
        // 同一個識別字只能註冊一次，否則系統會直接終止 App，所以每一批都用新的識別字
        let identifier = DownloadManager.continuedTaskPrefix + UUID().uuidString
        DispatchQueue.main.async {
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.stateQueue.async { self.attachContinuedTaskLocked(task) }
            }
            var submitted = false
            if registered {
                let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "下載漫畫", subtitle: comicName)
                request.strategy = .queue
                do {
                    try BGTaskScheduler.shared.submit(request)
                    DownloadManager.log.notice("背景工作已提交")
                    submitted = true
                } catch {
                    DownloadManager.log.error("背景工作提交失敗：\(String(describing: error), privacy: .public)")
                }
            }
            // 申請失敗時仍照常下載，只是切到背景後會像 iOS 26 以下一樣很快被暫停
            if !submitted {
                self.stateQueue.async { self.continuedTaskRequested = false }
            }
        }
    }

    /// 系統開始執行背景工作。若排隊期間佇列已經跑完，或這一批已經有背景工作，就直接結束
    @available(iOS 26.0, *)
    private func attachContinuedTaskLocked(_ task: BGContinuedProcessingTask) {
        guard continuedTask == nil, activeJob != nil || !pending.isEmpty else {
            task.setTaskCompleted(success: true)
            return
        }
        continuedTask = task
        DownloadManager.log.notice("背景工作開始執行")
        // 螢幕鎖定時系統會收回，使用者在系統的進度畫面按停止也會觸發，兩者無法分辨
        task.expirationHandler = {
            DownloadManager.log.error("背景工作被系統終止（expiration）")
            self.stateQueue.async { self.pauseForExpirationLocked() }
        }
        updateContinuedProgressLocked()
        if let job = activeJob { updateContinuedTitleLocked(job: job) }
    }

    /// 背景工作被終止：暫停佇列，不再開始下一集。正在下載的這一集不取消，App 被暫停時跟著凍結，
    /// 回到前景後接著下載；要真的取消只能在 App 內刪除。呼叫前必須已在 stateQueue 上
    private func pauseForExpirationLocked() {
        paused = true
        finishContinuedTaskLocked(success: false)
        // 若被終止時 App 其實在前景（例如在系統進度畫面按停止後馬上回來），不會再收到 didBecomeActive，這裡補檢查
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else { return }
            self.stateQueue.async { self.resumeIfPausedLocked() }
        }
    }

    /// 回到前景時接著下載暫停的佇列，並重新申請背景工作（只能在前景申請）。呼叫前必須已在 stateQueue 上
    private func resumeIfPausedLocked() {
        guard paused else { return }
        paused = false
        guard let first = activeJob ?? pending.first else { return }
        DownloadManager.log.notice("回到前景，繼續暫停的下載佇列")
        batchTotal = pending.count + (activeJob == nil ? 0 : 1)
        batchDone = 0
        requestContinuedTaskIfNeededLocked(comicName: first.comicName)
        startNextIfNeeded()
    }

    /// 佇列清空或被終止時結束背景工作並重置這一批的計數。呼叫前必須已在 stateQueue 上
    private func finishContinuedTaskLocked(success: Bool) {
        if #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask {
            task.setTaskCompleted(success: success)
            DownloadManager.log.notice("背景工作結束，成功 \(success)")
        }
        continuedTask = nil
        continuedTaskRequested = false
        batchTotal = 0
        batchDone = 0
    }

    /// 進度條顯示目前這一集的進度，下一集開始時歸零重新計算；集與集之間的休息時間停在上一集的進度。
    /// 系統會監看進度，太久沒有前進的工作可能被強制終止，所以每一頁都要更新。呼叫前必須已在 stateQueue 上
    private func updateContinuedProgressLocked() {
        guard #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask,
              activeJob != nil else { return }
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = Int64(min(activeProgress, 1) * 100)
    }

    /// 標題顯示這一批的第幾集，副標題顯示這一集的頁數。呼叫前必須已在 stateQueue 上
    private func updateContinuedTitleLocked(job: Job, page: Int? = nil, pageCount: Int? = nil) {
        guard #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask else { return }
        var subtitle = "\(job.comicName) \(job.episodeName)"
        if let page = page, let pageCount = pageCount {
            subtitle += " 第 \(page)/\(pageCount) 頁"
        }
        task.updateTitle("下載漫畫 \(batchDone + 1)/\(batchTotal)", subtitle: subtitle)
    }

    // MARK: - 紀錄存取

    private func updateRecord(job: Job, folder: String, pageFiles: [String], completed: Bool) {
        stateQueue.sync {
            guard !cancelledIds.contains(job.id) else { return }
            var record = records[job.comicId]
                ?? ComicRecord(comicId: job.comicId, name: job.comicName, episodes: [], updatedAt: 0)
            let entry = EpisodeRecord(key: job.key, url: job.episodeUrl, name: job.episodeName, order: job.order,
                                      folder: folder, pageFiles: pageFiles, completed: completed)
            if let index = record.episodes.firstIndex(where: { $0.key == job.key }) {
                record.episodes[index] = entry
            } else {
                record.episodes.append(entry)
            }
            record.updatedAt = Date().timeIntervalSince1970
            records[job.comicId] = record
            saveRecordLocked(record)
        }
    }

    /// 呼叫前必須已在 stateQueue 上
    private func saveRecordLocked(_ record: ComicRecord) {
        let folder = comicFolderURL(record.comicId)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        }
    }

    /// 呼叫前必須已在 stateQueue 上
    private func removeComicLocked(_ comicId: String) {
        records.removeValue(forKey: comicId)
        try? fileManager.removeItem(at: comicFolderURL(comicId))
    }

    private func loadAllRecords() {
        guard let folders = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            let manifest = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let record = try? JSONDecoder().decode(ComicRecord.self, from: data) else { continue }
            records[record.comicId] = record
        }
    }

    // MARK: - 路徑與工具

    private func comicFolderURL(_ comicId: String) -> URL {
        return rootURL.appendingPathComponent(DownloadManager.folderName(for: comicId), isDirectory: true)
    }

    private func episodeFolderURL(comicId: String, folder: String) -> URL {
        return comicFolderURL(comicId).appendingPathComponent(folder, isDirectory: true)
    }

    private func fileExists(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size > 0
    }

    /// 網址裡的 / ? = & 不能當資料夾名稱，換成底線
    private static func folderName(for key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(key.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private static func jobId(_ comicId: String, _ key: String) -> String {
        return comicId + "|" + key
    }

    /// 呼叫前必須已在 stateQueue 上
    private func postChange(comicId: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: DownloadManager.didChangeNotification, object: nil,
                                            userInfo: ["comicId": comicId])
        }
    }
}
