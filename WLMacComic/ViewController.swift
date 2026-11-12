//
//  ViewController.swift
//  WLMacComic
//
//  原生 macOS 版：漫畫列表（全部／收藏）→ 話數列表 → 閱讀器
//  閱讀進度、收藏、閱讀模式與 iOS 共用同一套儲存（ReadingProgress / FavoriteComics / ReadingModeStore）
//

import Cocoa

private struct MacComic {
    let id: String
    let name: String

    var coverURL: URL? { URL(string: "https://www.8comic.com/pics/0/\(id).jpg") }
}

private enum MacScreen {
    case library
    case episodes
    case reader
}

private enum LibrarySource: Int {
    case all = 0
    case favorites = 1
}

/// 由上往下排的座標系。NSScrollView 的 documentView 不翻轉的話原點在左下，內容會從底部開始
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate,
                            NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

    private static let host = URL(string: "https://www.8comic.com/")!

    // MARK: - 資料

    private var comics = [MacComic]()
    private var visibleComics = [MacComic]()
    private var librarySource = LibrarySource.all
    private var selectedComic: Comic?
    private var episodes = [Episode]()
    private var lastRead: ReadingProgress.Entry?
    private var lastReadIndex: Int?
    private var screen: MacScreen = .library
    private var loadToken = UUID()
    private var loadTimer: Timer?

    // MARK: - 閱讀器狀態

    private var currentEpisodeIndex: Int?
    private var pageURLs = [URL]()
    private var pageReferer = ViewController.host.absoluteString
    private var pageViews = [MacPageView]()
    private var currentPage = 0
    private var readingMode: ReadingMode = .horizontal
    /// 目前頁前後各保留幾頁的圖片，超出範圍的釋放記憶體
    private static let keepRange = 6
    private static let prefetchAhead = 3
    private var keyMonitor: Any?

    // MARK: - UI

    private let header = NSView()
    private let backButton = NSButton(title: "返回", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "漫畫")
    /// 列表頁沒有返回鈕，標題改貼齊左邊
    private lazy var titleAfterBack = titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 12)
    private lazy var titleAtEdge = titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24)

    private let libraryActions = NSStackView()
    private let sourceControl = NSSegmentedControl(labels: ["全部", "收藏"], trackingMode: .selectOne, target: nil, action: nil)
    private let searchField = NSSearchField()

    private let episodeActions = NSStackView()
    private let continueButton = NSButton(title: "繼續閱讀", target: nil, action: nil)
    private let favoriteButton = NSButton(title: "加入收藏", target: nil, action: nil)

    private let readerControls = NSStackView()
    private let previousButton = NSButton(title: "上一話", target: nil, action: nil)
    private let nextButton = NSButton(title: "下一話", target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: ["單頁", "條漫"], trackingMode: .selectOne, target: nil, action: nil)
    private let fullscreenButton = NSButton(title: "全螢幕", target: nil, action: nil)
    private let pageCountLabel = NSTextField(labelWithString: "")

    private let libraryScrollView = NSScrollView()
    private let collectionView = MacComicCollectionView()
    private let episodesScrollView = NSScrollView()
    private let episodeTable = MacEpisodeTableView()
    private let readerScrollView = NSScrollView()
    private let readerContent = FlippedView()
    private let pageStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        loadLibrary()

        NotificationCenter.default.addObserver(self, selector: #selector(favoritesDidChange),
                                               name: FavoriteComics.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(readerDidScroll),
                                               name: NSView.boundsDidChangeNotification,
                                               object: readerScrollView.contentView)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // viewDidLoad 時還沒有 window，makeFirstResponder 沒作用，要等畫面出現再把鍵盤焦點交給漫畫列表
        if screen == .library { focusLibrary() }
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    // MARK: - 版面

    private func buildInterface() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(backButton)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        configureLibraryActions()
        configureEpisodeActions()
        configureReaderControls()
        for actions in [libraryActions, episodeActions, readerControls] {
            actions.orientation = .horizontal
            actions.alignment = .centerY
            actions.spacing = 12
            actions.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(actions)
        }

        configureLibrary()
        configureEpisodes()
        configureReader()

        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        var constraints: [NSLayoutConstraint] = [
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 64),

            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            searchField.widthAnchor.constraint(equalToConstant: 250),

            libraryScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            libraryScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            libraryScrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            libraryScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            episodesScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            episodesScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            episodesScrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            episodesScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            readerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            readerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            readerScrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            readerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ]
        for actions in [libraryActions, episodeActions, readerControls] {
            constraints += [
                actions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
                actions.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -18),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        showScreen(.library)
    }

    private func configureLibraryActions() {
        sourceControl.selectedSegment = LibrarySource.all.rawValue
        sourceControl.target = self
        sourceControl.action = #selector(changeLibrarySource)
        searchField.placeholderString = "搜尋漫畫"
        searchField.delegate = self
        libraryActions.addArrangedSubview(sourceControl)
        libraryActions.addArrangedSubview(searchField)
    }

    private func configureEpisodeActions() {
        continueButton.bezelStyle = .rounded
        continueButton.target = self
        continueButton.action = #selector(continueReading)
        favoriteButton.bezelStyle = .rounded
        favoriteButton.target = self
        favoriteButton.action = #selector(toggleFavorite)
        episodeActions.addArrangedSubview(continueButton)
        episodeActions.addArrangedSubview(favoriteButton)
    }

    private func configureReaderControls() {
        previousButton.bezelStyle = .rounded
        previousButton.target = self
        previousButton.action = #selector(showPreviousEpisode)
        nextButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(showNextEpisode)
        modeControl.target = self
        modeControl.action = #selector(changeReadingMode)
        modeControl.toolTip = "單頁：每頁縮放到視窗高度；條漫：限寬、頁面相連"
        fullscreenButton.bezelStyle = .rounded
        fullscreenButton.target = self
        fullscreenButton.action = #selector(toggleFullscreen)
        pageCountLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pageCountLabel.textColor = .secondaryLabelColor
        readerControls.addArrangedSubview(previousButton)
        readerControls.addArrangedSubview(pageCountLabel)
        readerControls.addArrangedSubview(nextButton)
        readerControls.addArrangedSubview(modeControl)
        readerControls.addArrangedSubview(fullscreenButton)
    }

    private func configureLibrary() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 166, height: 282)
        layout.sectionInset = NSEdgeInsets(top: 24, left: 32, bottom: 28, right: 32)
        layout.minimumInteritemSpacing = 24
        layout.minimumLineSpacing = 26
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.onActivateSelection = { [weak self] in self?.openSelectedComic() }
        collectionView.register(MacComicPosterItem.self,
                                forItemWithIdentifier: MacComicPosterItem.reuseIdentifier)
        collectionView.backgroundColors = [.clear]

        // 封面按右鍵：加入／取消收藏
        let menu = NSMenu()
        menu.delegate = self
        collectionView.menu = menu

        libraryScrollView.hasVerticalScroller = true
        libraryScrollView.drawsBackground = false
        libraryScrollView.documentView = collectionView
        libraryScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(libraryScrollView)
    }

    private func configureEpisodes() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("episode"))
        column.title = "話數"
        episodeTable.addTableColumn(column)
        episodeTable.headerView = nil
        episodeTable.rowHeight = 46
        episodeTable.intercellSpacing = NSSize(width: 0, height: 1)
        episodeTable.dataSource = self
        episodeTable.delegate = self
        // 用點擊事件開啟，不靠選取變化判斷：程式改選取（例如按下一話）時才不會又重開一次
        episodeTable.target = self
        episodeTable.action = #selector(episodeClicked)
        episodeTable.onReturn = { [weak self] in self?.openSelectedEpisode() }
        episodesScrollView.documentView = episodeTable
        episodesScrollView.hasVerticalScroller = true
        episodesScrollView.drawsBackground = false
        episodesScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(episodesScrollView)
    }

    private func configureReader() {
        pageStack.orientation = .vertical
        pageStack.alignment = .centerX
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        readerContent.translatesAutoresizingMaskIntoConstraints = false
        readerContent.addSubview(pageStack)
        readerScrollView.documentView = readerContent
        readerScrollView.contentView.postsBoundsChangedNotifications = true
        let clip = readerScrollView.contentView
        NSLayoutConstraint.activate([
            readerContent.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            readerContent.topAnchor.constraint(equalTo: clip.topAnchor),
            readerContent.widthAnchor.constraint(equalTo: clip.widthAnchor),
            pageStack.leadingAnchor.constraint(equalTo: readerContent.leadingAnchor, constant: 24),
            pageStack.trailingAnchor.constraint(equalTo: readerContent.trailingAnchor, constant: -24),
            pageStack.topAnchor.constraint(equalTo: readerContent.topAnchor, constant: 12),
            pageStack.bottomAnchor.constraint(equalTo: readerContent.bottomAnchor, constant: -12),
        ])
        readerScrollView.hasVerticalScroller = true
        readerScrollView.drawsBackground = true
        readerScrollView.backgroundColor = .black
        readerScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(readerScrollView)
    }

    // MARK: - 畫面切換

    private func showScreen(_ next: MacScreen) {
        screen = next
        libraryScrollView.isHidden = next != .library
        episodesScrollView.isHidden = next != .episodes
        readerScrollView.isHidden = next != .reader
        libraryActions.isHidden = next != .library
        episodeActions.isHidden = next != .episodes
        readerControls.isHidden = next != .reader
        backButton.isHidden = next == .library
        // 先關掉再開，避免兩條同時生效造成約束衝突
        if next == .library {
            titleAfterBack.isActive = false
            titleAtEdge.isActive = true
        } else {
            titleAtEdge.isActive = false
            titleAfterBack.isActive = true
        }
        statusLabel.isHidden = true

        switch next {
        case .library:
            titleLabel.stringValue = librarySource == .favorites ? "收藏" : "漫畫"
            applyFilter()
            focusLibrary()
        case .episodes:
            titleLabel.stringValue = selectedComic?.getName() ?? "話數"
            refreshLastRead()
            episodeTable.reloadData()
            updateEpisodeActions()
            view.window?.makeFirstResponder(episodeTable)
        case .reader:
            updateReaderTitle()
            view.window?.makeFirstResponder(readerScrollView)
        }
    }

    @objc private func goBack() {
        loadToken = UUID()
        loadTimer?.invalidate()
        switch screen {
        case .library:
            break
        case .episodes:
            showScreen(.library)
        case .reader:
            clearPages()
            showScreen(.episodes)
            if let row = currentEpisodeIndex, episodes.indices.contains(row) {
                episodeTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                episodeTable.scrollRowToVisible(row)
            }
        }
    }

    private func showStatus(_ text: String?) {
        statusLabel.stringValue = text ?? ""
        statusLabel.isHidden = text == nil
    }

    // MARK: - 漫畫列表

    private func loadLibrary() {
        guard let url = Bundle.main.url(forResource: "AllComics", withExtension: "plist"),
              let root = NSDictionary(contentsOf: url),
              let entries = root["comics"] as? [[String: String]] else {
            showStatus("無法載入漫畫")
            return
        }
        comics = entries.compactMap { entry in
            guard let id = entry["comic_id"], let name = entry["name"] else { return nil }
            return MacComic(id: id, name: name)
        }
        applyFilter()
    }

    private func favoriteComics() -> [MacComic] {
        FavoriteComics.listAllFavorite().compactMap { dict in
            guard let id = dict.object(forKey: "comic_id") as? String,
                  let name = dict.object(forKey: "name") as? String else { return nil }
            return MacComic(id: id, name: name)
        }
    }

    private func applyFilter() {
        let source = librarySource == .favorites ? favoriteComics() : comics
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleComics = query.isEmpty ? source : source.filter { $0.name.localizedCaseInsensitiveContains(query) }
        collectionView.reloadData()
        guard screen == .library else { return }
        if visibleComics.isEmpty {
            showStatus(!query.isEmpty ? "找不到符合的漫畫"
                       : librarySource == .favorites ? "還沒有收藏任何漫畫（在封面按右鍵加入）" : "沒有漫畫")
        } else {
            showStatus(nil)
        }
    }

    @objc private func changeLibrarySource() {
        librarySource = LibrarySource(rawValue: sourceControl.selectedSegment) ?? .all
        titleLabel.stringValue = librarySource == .favorites ? "收藏" : "漫畫"
        applyFilter()
        collectionView.scroll(.zero)
    }

    @objc private func favoritesDidChange() {
        if librarySource == .favorites { applyFilter() }
        if screen == .episodes { updateEpisodeActions() }
    }

    override func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleComics.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: MacComicPosterItem.reuseIdentifier,
                                           for: indexPath) as! MacComicPosterItem
        item.configure(with: visibleComics[indexPath.item])
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        // Selection is kept visible like tvOS focus; activation opens the comic.
    }

    private func openSelectedComic() {
        guard let index = collectionView.selectionIndexPaths.first?.item,
              visibleComics.indices.contains(index) else { return }
        openComic(visibleComics[index])
    }

    /// 上次開啟的漫畫，回到列表時選回它
    private var lastOpenedComicId: String?

    /// 鍵盤焦點交給漫畫列表；回到列表時選回上次開啟的漫畫
    private func focusLibrary() {
        guard let window = view.window else { return }
        window.makeFirstResponder(collectionView)
        if let id = lastOpenedComicId, let index = visibleComics.firstIndex(where: { $0.id == id }) {
            selectComic(at: index)
        }
    }

    private func selectComic(at index: Int) {
        guard visibleComics.indices.contains(index) else { return }
        let indexPath: Set<IndexPath> = [IndexPath(item: index, section: 0)]
        collectionView.deselectAll(nil)
        collectionView.selectItems(at: indexPath, scrollPosition: .nearestHorizontalEdge)
        collectionView.scrollToItems(at: indexPath, scrollPosition: .centeredVertically)
    }

    // 搜尋框按 ↓ 或 Enter：焦點移到結果，選第一本
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField,
              commandSelector == #selector(NSResponder.moveDown(_:)) ||
              commandSelector == #selector(NSResponder.insertNewline(_:)),
              !visibleComics.isEmpty else { return false }
        view.window?.makeFirstResponder(collectionView)
        selectComic(at: 0)
        return true
    }

    private func makeComic(_ record: MacComic) -> Comic {
        let comic = R8Comic.get().generatorFakeComic(record.id, name: record.name)
        comic.setIconUrl(record.coverURL?.absoluteString ?? "")
        comic.setSmallIconUrl(record.coverURL?.absoluteString ?? "")
        return comic
    }

    // MARK: 右鍵選單

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let event = NSApp.currentEvent else { return }
        let point = collectionView.convert(event.locationInWindow, from: nil)
        guard let index = collectionView.indexPathForItem(at: point)?.item,
              visibleComics.indices.contains(index) else { return }
        let comic = makeComic(visibleComics[index])
        let isFavorite = FavoriteComics.checkComicIsMyFavorite(comic)
        let item = NSMenuItem(title: isFavorite ? "取消收藏" : "加入收藏",
                              action: #selector(toggleFavoriteFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = comic
        menu.addItem(item)
    }

    @objc private func toggleFavoriteFromMenu(_ sender: NSMenuItem) {
        guard let comic = sender.representedObject as? Comic else { return }
        if FavoriteComics.checkComicIsMyFavorite(comic) {
            FavoriteComics.removeComicFromMyFavorite(comic)
        } else {
            FavoriteComics.addComicToMyFavorite(comic)
        }
    }

    // MARK: - 話數列表

    private func openComic(_ record: MacComic) {
        lastOpenedComicId = record.id
        let comic = makeComic(record)
        selectedComic = comic
        episodes = []
        currentEpisodeIndex = nil
        readingMode = ReadingModeStore.mode(for: comic.getId()) ?? .horizontal
        showScreen(.episodes)
        showStatus("載入話數…")

        let token = UUID()
        loadToken = token
        loadTimer?.invalidate()
        // SDK 讀取失敗時不會呼叫 callback
        loadTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self = self, self.loadToken == token, self.episodes.isEmpty else { return }
            self.showStatus("暫時無法載入話數")
        }

        R8Comic.get().loadComicDetail(comic) { [weak self] detail in
            let loaded = detail.getEpisode()
            DispatchQueue.main.async {
                guard let self = self, self.loadToken == token else { return }
                self.loadTimer?.invalidate()
                self.episodes = loaded
                self.refreshLastRead()
                self.episodeTable.reloadData()
                self.updateEpisodeActions()
                self.showStatus(loaded.isEmpty ? "目前沒有話數" : nil)
                if let row = self.lastReadIndex {
                    self.episodeTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    self.episodeTable.scrollRowToVisible(row)
                }
            }
        }
    }

    private func refreshLastRead() {
        guard let comic = selectedComic else { lastRead = nil; lastReadIndex = nil; return }
        lastRead = ReadingProgress.progress(for: comic.getId())
        if let entry = lastRead {
            lastReadIndex = episodes.firstIndex { ReadingProgress.normalizedEpisodeUrl($0.getUrl()) == entry.episodeUrl }
        } else {
            lastReadIndex = nil
        }
    }

    private func updateEpisodeActions() {
        continueButton.isEnabled = lastReadIndex != nil
        if let row = lastReadIndex, let entry = lastRead {
            continueButton.title = "繼續閱讀：\(episodes[row].getName()) 第 \(entry.page + 1) 頁"
        } else {
            continueButton.title = "繼續閱讀"
        }
        let isFavorite = selectedComic.map { FavoriteComics.checkComicIsMyFavorite($0) } ?? false
        favoriteButton.title = isFavorite ? "取消收藏" : "加入收藏"
    }

    @objc private func continueReading() {
        guard let row = lastReadIndex, let entry = lastRead else { return }
        openEpisode(at: row, startPage: entry.page)
    }

    @objc private func toggleFavorite() {
        guard let comic = selectedComic else { return }
        if FavoriteComics.checkComicIsMyFavorite(comic) {
            FavoriteComics.removeComicFromMyFavorite(comic)
        } else {
            FavoriteComics.addComicToMyFavorite(comic)
        }
        updateEpisodeActions()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { episodes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: MacEpisodeCellView.reuseIdentifier, owner: self) as? MacEpisodeCellView)
            ?? MacEpisodeCellView()
        var detail: String?
        if row == lastReadIndex, let entry = lastRead {
            detail = "上次看到第 \(entry.page + 1) 頁"
        }
        cell.configure(title: episodes[row].getName(), detail: detail)
        return cell
    }

    @objc private func episodeClicked() {
        let row = episodeTable.clickedRow
        guard episodes.indices.contains(row) else { return }
        let startPage = row == lastReadIndex ? (lastRead?.page ?? 0) : 0
        openEpisode(at: row, startPage: startPage)
    }

    private func openSelectedEpisode() {
        let row = episodeTable.selectedRow
        guard episodes.indices.contains(row) else { return }
        let startPage = row == lastReadIndex ? (lastRead?.page ?? 0) : 0
        openEpisode(at: row, startPage: startPage)
    }

    // MARK: - 閱讀器

    private func openEpisode(at index: Int, startPage: Int = 0) {
        guard episodes.indices.contains(index) else { return }
        currentEpisodeIndex = index
        clearPages()
        showScreen(.reader)
        showStatus("載入漫畫頁面…")

        let token = UUID()
        loadToken = token
        let episode = episodes[index]
        loadTimer?.invalidate()
        loadTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self = self, self.loadToken == token, self.pageURLs.isEmpty else { return }
            self.showStatus("無法載入漫畫頁面")
        }
        // 話數列表給的是相對網址，先轉成絕對網址；它同時是圖片的 Referer
        if !episode.getUrl().hasPrefix("http") {
            episode.setUrl("https://www.8comic.com/view/" + episode.getUrl())
        }
        let episodeReferer = episode.getUrl()
        R8Comic.get().loadEpisodeDetail(episode) { [weak self] loadedEpisode in
            loadedEpisode.setUpPages()
            let urls = loadedEpisode.getImageUrlList().compactMap { value -> URL? in
                if let url = URL(string: value), url.scheme != nil { return url }
                return URL(string: value, relativeTo: ViewController.host)?.absoluteURL
            }
            let referer = URL(string: loadedEpisode.getUrl(), relativeTo: ViewController.host)?.absoluteURL.absoluteString
                ?? episodeReferer
            DispatchQueue.main.async {
                guard let self = self, self.loadToken == token else { return }
                self.loadTimer?.invalidate()
                self.episodes[index] = loadedEpisode
                self.pageURLs = urls
                self.pageReferer = referer
                self.updateReaderTitle()
                self.showStatus(urls.isEmpty ? "無法解析這一話的漫畫頁面" : nil)
                self.buildPages(startPage: min(max(startPage, 0), max(urls.count - 1, 0)))
            }
        }
    }

    private func clearPages() {
        pageViews.forEach { $0.cancel(); $0.removeFromSuperview() }
        pageViews = []
        pageURLs = []
        currentPage = 0
        pageCountLabel.stringValue = ""
    }

    /// 依目前的閱讀模式建立每頁的佔位 view，圖片等捲到附近才載入
    private func buildPages(startPage: Int) {
        pageViews.forEach { $0.cancel(); $0.removeFromSuperview() }
        pageViews = []
        modeControl.selectedSegment = readingMode == .vertical ? 1 : 0
        pageStack.spacing = readingMode == .vertical ? 0 : 16

        let clip = readerScrollView.contentView
        for url in pageURLs {
            let page = MacPageView(url: url)
            pageStack.addArrangedSubview(page)
            var constraints = [page.widthAnchor.constraint(lessThanOrEqualTo: pageStack.widthAnchor)]
            let fill = page.widthAnchor.constraint(equalTo: pageStack.widthAnchor)
            fill.priority = .defaultLow
            constraints.append(fill)
            if readingMode == .vertical {
                // 條漫原圖多半只有 700–900 px 寬，限寬避免放大糊掉
                constraints.append(page.widthAnchor.constraint(lessThanOrEqualToConstant: 900))
            } else {
                // 單頁：整頁塞進視窗高度，翻頁鍵剛好一頁
                constraints.append(page.heightAnchor.constraint(lessThanOrEqualTo: clip.heightAnchor, constant: -24))
            }
            NSLayoutConstraint.activate(constraints)
            pageViews.append(page)
        }

        currentPage = startPage
        readerContent.layoutSubtreeIfNeeded()
        scrollToPage(startPage)
        updateVisiblePages()
    }

    @objc private func readerDidScroll() {
        guard screen == .reader, !pageViews.isEmpty else { return }
        updateVisiblePages()
    }

    private func pageFrame(_ index: Int) -> NSRect {
        pageViews[index].convert(pageViews[index].bounds, to: readerContent)
    }

    /// 視窗上方三分之一處落在哪一頁，就算目前頁
    private func pageIndexInView() -> Int {
        let visible = readerScrollView.documentVisibleRect
        let probe = visible.minY + visible.height / 3
        for index in pageViews.indices where pageFrame(index).maxY > probe {
            return index
        }
        return max(pageViews.count - 1, 0)
    }

    private func updateVisiblePages() {
        guard !pageViews.isEmpty else { return }
        let page = pageIndexInView()
        if page != currentPage || pageCountLabel.stringValue.isEmpty {
            currentPage = page
            saveProgress()
        }
        pageCountLabel.stringValue = "\(currentPage + 1) / \(pageViews.count)"

        // 載入畫面上看得到的頁面和前後幾頁；離太遠的釋放圖片
        let visible = readerScrollView.documentVisibleRect
        for index in pageViews.indices {
            let frame = pageFrame(index)
            let isVisible = frame.intersects(visible)
            let isNear = index >= currentPage - 1 && index <= currentPage + Self.prefetchAhead
            if isVisible || isNear {
                load(page: index)
            } else if abs(index - currentPage) > Self.keepRange {
                pageViews[index].unload()
            }
        }
    }

    private func load(page index: Int) {
        let page = pageViews[index]
        guard page.needsLoad else { return }
        let token = loadToken
        page.load(referer: pageReferer) { [weak self, weak page] image in
            guard let self = self, let page = page, self.loadToken == token,
                  let index = self.pageViews.firstIndex(where: { $0 === page }) else { return }
            guard let image = image else { return }
            // 目前頁上方的頁面載入後高度改變，補償捲動位置，畫面才不會跳
            let before = self.pageFrame(index)
            let visible = self.readerScrollView.documentVisibleRect
            let isAbove = before.maxY <= visible.minY + 1
            page.show(image)
            self.readerContent.layoutSubtreeIfNeeded()
            if isAbove {
                let delta = self.pageFrame(index).height - before.height
                if delta != 0 { self.scroll(toY: visible.minY + delta) }
            }
        }
    }

    private func scroll(toY y: CGFloat) {
        let clip = readerScrollView.contentView
        let maxY = max(readerContent.frame.height - clip.bounds.height, 0)
        clip.scroll(to: NSPoint(x: 0, y: min(max(y, 0), maxY)))
        readerScrollView.reflectScrolledClipView(clip)
    }

    private func scrollToPage(_ index: Int) {
        guard pageViews.indices.contains(index) else { return }
        readerContent.layoutSubtreeIfNeeded()
        scroll(toY: pageFrame(index).minY - 12)
    }

    private func saveProgress() {
        guard let comic = selectedComic, let row = currentEpisodeIndex, episodes.indices.contains(row) else { return }
        let episode = episodes[row]
        ReadingProgress.save(comicId: comic.getId(), episodeUrl: episode.getUrl(),
                             episodeName: episode.getName(), page: currentPage)
    }

    private func updateReaderTitle() {
        guard let row = currentEpisodeIndex, episodes.indices.contains(row) else {
            titleLabel.stringValue = selectedComic?.getName() ?? "閱讀"
            return
        }
        titleLabel.stringValue = "\(selectedComic?.getName() ?? "")　\(episodes[row].getName())"
        previousButton.isEnabled = row > 0
        nextButton.isEnabled = row + 1 < episodes.count
    }

    @objc private func showPreviousEpisode() {
        guard let row = currentEpisodeIndex, row > 0 else { return }
        openEpisode(at: row - 1)
    }

    @objc private func showNextEpisode() {
        guard let row = currentEpisodeIndex, row + 1 < episodes.count else { return }
        openEpisode(at: row + 1)
    }

    @objc private func changeReadingMode() {
        readingMode = modeControl.selectedSegment == 1 ? .vertical : .horizontal
        if let comic = selectedComic {
            ReadingModeStore.setManual(readingMode, for: comic.getId())
        }
        guard !pageURLs.isEmpty else { return }
        buildPages(startPage: currentPage)
    }

    @objc private func toggleFullscreen() {
        view.window?.toggleFullScreen(nil)
    }

    // MARK: - 鍵盤

    private func goToPage(_ index: Int) {
        if index >= pageViews.count {
            showNextEpisode()
        } else if index < 0 {
            showPreviousEpisode()
        } else {
            scrollToPage(index)
        }
    }

    /// 單頁模式一次一頁；條漫模式上下鍵與空白鍵捲動一個畫面，左右鍵跳頁
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // 搜尋框輸入中不攔
        if view.window?.firstResponder is NSText { return false }
        guard event.window === view.window else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }

        if event.keyCode == 53 { // Esc
            guard screen != .library else { return false }
            goBack()
            return true
        }
        if screen == .episodes {
            // Collection view 也會把方向鍵當成漫畫選取。明確由話數畫面處理，
            // 即使焦點意外留在封面列表，也只移動目前漫畫的話數選取列。
            switch event.keyCode {
            case 125: // ↓
                moveEpisodeSelection(by: 1)
                return true
            case 126: // ↑
                moveEpisodeSelection(by: -1)
                return true
            case 36, 76: // Return、數字鍵盤 Enter：開啟選取的話數。
                // 焦點若還留在（隱藏的）封面列表，Return 會被它當成重開那本漫畫，所以在這裡先攔下
                guard episodes.indices.contains(episodeTable.selectedRow) else { return true }
                openSelectedEpisode()
                return true
            default:
                return false
            }
        }
        guard screen == .reader, !pageViews.isEmpty else { return false }

        let shift = event.modifierFlags.contains(.shift)
        let visible = readerScrollView.documentVisibleRect
        let atBottom = visible.maxY >= readerContent.frame.height - 2
        let atTop = visible.minY <= 1
        switch event.keyCode {
        case 124: // →
            goToPage(currentPage + 1)
        case 123: // ←
            goToPage(currentPage - 1)
        case 125, 49 where !shift: // ↓、空白鍵
            if readingMode == .vertical {
                if atBottom { showNextEpisode() } else { scroll(toY: visible.minY + visible.height * 0.9) }
            } else {
                goToPage(currentPage + 1)
            }
        case 126, 49: // ↑、Shift+空白鍵
            if readingMode == .vertical {
                if atTop { showPreviousEpisode() } else { scroll(toY: visible.minY - visible.height * 0.9) }
            } else {
                goToPage(currentPage - 1)
            }
        default:
            return false
        }
        return true
    }

    private func moveEpisodeSelection(by offset: Int) {
        guard !episodes.isEmpty else { return }
        let current = episodeTable.selectedRow
        let start = episodes.indices.contains(current) ? current : (offset > 0 ? -1 : episodes.count)
        let row = min(max(start + offset, 0), episodes.count - 1)
        episodeTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        episodeTable.scrollRowToVisible(row)
        view.window?.makeFirstResponder(episodeTable)
    }
}

// MARK: - 話數列表

/// 按 Return 開啟選取的話數
private final class MacEpisodeTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class MacEpisodeCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("MacEpisodeCellView")

    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseIdentifier
        titleField.font = .systemFont(ofSize: 16, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        detailField.font = .systemFont(ofSize: 13, weight: .medium)
        detailField.textColor = .controlAccentColor
        let stack = NSStackView(views: [titleField, detailField])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textField = titleField
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, detail: String?) {
        titleField.stringValue = title
        detailField.stringValue = detail ?? ""
        detailField.isHidden = detail == nil
    }
}

// MARK: - 閱讀器的單頁

private final class MacPageView: NSView {
    let url: URL
    private let imageView = NSImageView()
    private let failureLabel = NSTextField(labelWithString: "載入失敗")
    private var aspectConstraint: NSLayoutConstraint!
    private var isLoading = false
    private var task: URLSessionDataTask?

    var needsLoad: Bool { imageView.image == nil && !isLoading }

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // NSImageView 的 intrinsic size 是原圖像素大小，預設抗壓縮優先度 750 高於視窗維持大小的 500，
        // 原圖較寬時會把整個視窗撐到超出螢幕。調到最低，尺寸完全由頁面約束決定
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            imageView.setContentCompressionResistancePriority(.init(1), for: orientation)
            imageView.setContentHuggingPriority(.init(1), for: orientation)
        }
        addSubview(imageView)
        failureLabel.textColor = .secondaryLabelColor
        failureLabel.isHidden = true
        failureLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(failureLabel)

        // 還沒載入前先用一般漫畫頁的比例佔位
        aspectConstraint = heightAnchor.constraint(equalTo: widthAnchor, multiplier: 1.42)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            failureLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            failureLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            aspectConstraint,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func load(referer: String, completion: @escaping (NSImage?) -> Void) {
        isLoading = true
        failureLabel.isHidden = true
        task = MacImageLoader.pages.load(url: url, referer: referer) { [weak self] image in
            guard let self = self else { return }
            self.isLoading = false
            self.task = nil
            if image == nil { self.failureLabel.isHidden = false }
            completion(image)
        }
    }

    func show(_ image: NSImage) {
        imageView.image = image
        guard image.size.width > 0 else { return }
        aspectConstraint.isActive = false
        aspectConstraint = heightAnchor.constraint(equalTo: widthAnchor, multiplier: image.size.height / image.size.width)
        aspectConstraint.isActive = true
    }

    /// 釋放圖片但保留比例，捲回來時版面不變
    func unload() {
        cancel()
        imageView.image = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }
}

// MARK: - 封面

private final class MacComicPosterItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("MacComicPosterItem")
    private let coverView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var comicID: String?

    override var isSelected: Bool {
        didSet { updateFocusStyle(animated: true) }
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.masksToBounds = false
        view = root
        coverView.imageScaling = .scaleProportionallyUpOrDown
        coverView.wantsLayer = true
        coverView.layer?.cornerRadius = 9
        coverView.layer?.masksToBounds = true
        coverView.layer?.borderWidth = 0
        coverView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(coverView)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            coverView.topAnchor.constraint(equalTo: root.topAnchor),
            coverView.heightAnchor.constraint(equalTo: coverView.widthAnchor, multiplier: 1.38),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: coverView.bottomAnchor, constant: 9),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
        ])
        updateFocusStyle(animated: false)
    }

    func configure(with comic: MacComic) {
        comicID = comic.id
        titleLabel.stringValue = comic.name
        coverView.image = NSImage(named: NSImage.Name.folder)
        guard let url = comic.coverURL else { return }
        MacImageLoader.covers.load(url: url) { [weak self] image in
            guard let self = self, self.comicID == comic.id, let image = image else { return }
            self.coverView.image = image
        }
    }

    private func updateFocusStyle(animated: Bool) {
        let focused = isSelected
        guard let layer = coverView.layer else { return }
        // NSView 的 layer 錨點在左下角，直接縮放會往右上偏；先平移到中心再縮放
        let scale: CGFloat = focused ? 1.08 : 1
        let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
        if animated {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = layer.presentation()?.transform ?? layer.transform
            animation.toValue = transform
            animation.duration = 0.18
            animation.timingFunction = CAMediaTimingFunction(name: "easeOut")
            layer.add(animation, forKey: "focusTransform")
        }
        layer.transform = transform
        layer.borderWidth = focused ? 3 : 0
        layer.borderColor = NSColor.controlAccentColor.cgColor
        layer.shadowColor = NSColor.controlAccentColor.cgColor
        layer.shadowOpacity = focused ? 0.55 : 0
        layer.shadowRadius = focused ? 14 : 0
        layer.shadowOffset = .zero
        titleLabel.textColor = focused ? .controlAccentColor : .labelColor
    }
}

/// Lets arrow keys move the poster focus and uses Return or a mouse click to open it.
private final class MacComicCollectionView: NSCollectionView {
    var onActivateSelection: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // NSCollectionView 的 mouseDown 自己追蹤滑鼠，mouseUp 不一定會收到，改用手勢判斷點擊
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return、數字鍵盤 Enter
            onActivateSelection?()
        case 123, 124, 125, 126:
            moveSelection(keyCode: event.keyCode)
        default:
            super.keyDown(with: event)
        }
    }

    /// 內建的鍵盤導覽在這個 flow layout 下不會正常移動選取，自己依格子位置計算
    private func moveSelection(keyCode: UInt16) {
        let count = numberOfItems(inSection: 0)
        guard count > 0 else { return }
        guard let current = selectionIndexPaths.first?.item, current < count else {
            select(item: 0)
            return
        }
        let columns = columnCount(itemCount: count)
        var target = current
        switch keyCode {
        case 123: target = current - 1          // ←
        case 124: target = current + 1          // →
        case 126: target = current - columns    // ↑
        case 125:                               // ↓：最後一排不滿時停在最後一本
            target = current + columns
            if target >= count, current / columns < (count - 1) / columns { target = count - 1 }
        default: break
        }
        guard target >= 0, target < count, target != current else { return }
        select(item: target)
    }

    /// 第一排有幾本：數和第一本同一個 y 的格子
    private func columnCount(itemCount: Int) -> Int {
        guard let firstY = layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame.minY else { return 1 }
        var columns = 0
        while columns < itemCount,
              let frame = layoutAttributesForItem(at: IndexPath(item: columns, section: 0))?.frame,
              abs(frame.minY - firstY) < 1 {
            columns += 1
        }
        return max(columns, 1)
    }

    private func select(item: Int) {
        let selection: Set<IndexPath> = [IndexPath(item: item, section: 0)]
        deselectAll(nil)
        selectItems(at: selection, scrollPosition: [])
        // 只在選取框跑出畫面時才捲動，貼齊上緣或下緣
        scrollToItems(at: selection, scrollPosition: .nearestHorizontalEdge)
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard let indexPath = indexPathForItem(at: gesture.location(in: self)) else { return }
        let selection: Set<IndexPath> = [indexPath]
        if selectionIndexPaths != selection {
            deselectAll(nil)
            selectItems(at: selection, scrollPosition: [])
        }
        onActivateSelection?()
    }
}

// MARK: - 圖片載入

private final class MacImageLoader {
    static let covers = MacImageLoader(countLimit: 600)
    /// 漫畫頁圖檔大，只快取最近的幾十張
    static let pages = MacImageLoader(countLimit: 40)

    private let images = NSCache<NSString, NSImage>()
    private let session: URLSession

    private init(countLimit: Int) {
        images.countLimit = countLimit
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    /// 8comic 的圖片沒有正確的 Referer 會被擋
    @discardableResult
    func load(url: URL, referer: String = "https://www.8comic.com/",
              completion: @escaping (NSImage?) -> Void) -> URLSessionDataTask? {
        let key = url.absoluteString as NSString
        if let image = images.object(forKey: key) {
            DispatchQueue.main.async { completion(image) }
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        let task = session.dataTask(with: request) { [weak self] data, _, error in
            if (error as? URLError)?.code == .cancelled { return }
            let image = data.flatMap { NSImage(data: $0) }
            if let image = image { self?.images.setObject(image, forKey: key) }
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }
}
