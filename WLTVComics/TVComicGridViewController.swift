//
//  TVComicGridViewController.swift
//  WLTVComics
//
//  漫畫列表 — 用 UICollectionView 呈現海報風格的網格
//

import UIKit
import Kingfisher

class TVComicGridViewController: UIViewController {

    private var collectionView: UICollectionView!

    private var allComics = [Comic]()
    private var isSearching = false

    /// 分組資料（A-Z 拼音首字母）
    private var sectionTitles = [String]()
    private var sectionedComics = [String: [Comic]]()

    /// 搜尋結果（平面列表，不分組）
    private var filterComics = [Comic]()

    /// 記住列表捲動位置
    private static let scrollAnchorKey = "tv_grid_scroll_anchor"
    private var didRestoreScrollPosition = false

    /// 8comic 會擋掉沒有 Referer 的圖片請求
    private let refererModifier = AnyModifier { request in
        var r = request
        r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        return r
    }

    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private static let headerKind = UICollectionView.elementKindSectionHeader
    private static let headerId = "TVSectionHeader"

    private let searchButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        btn.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.isNavigationBarHidden = true

        setUpCollectionView()
        setUpActivityIndicator()
        setUpSearchButton()

        activityIndicator.startAnimating()
        WLComics.sharedInstance().loadAllComics { [weak self] comics in
            guard let self = self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let library = self.buildComicLibrary(from: comics)
                DispatchQueue.main.async {
                    self.allComics = comics
                    self.sectionTitles = library.titles
                    self.sectionedComics = library.sorted
                    self.activityIndicator.stopAnimating()
                    self.collectionView.reloadData()
                    self.restoreScrollPosition()
                    self.refreshComicsFromWeb()
                }
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(saveScrollPosition),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreScrollPosition()
    }

    private func refreshComicsFromWeb() {
        WLComics.sharedInstance().refreshComicsFromWeb { [weak self] updatedComics in
            guard let self = self, updatedComics.count > self.allComics.count else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let library = self.buildComicLibrary(from: updatedComics)
                DispatchQueue.main.async {
                    self.allComics = updatedComics
                    if !self.isSearching {
                        self.sectionTitles = library.titles
                        self.sectionedComics = library.sorted
                        self.collectionView.reloadData()
                    }
                }
            }
        }
    }

    // MARK: - Pinyin 分組

    /// 建立拼音首字母分組（跟 iOS 版 MasterViewController 一樣的邏輯）
    private func buildComicLibrary(from comics: [Comic]) -> (sorted: [String: [Comic]], titles: [String]) {
        // 先一次算好所有拼音，避免排序時重複做 CFStringTransform
        var pinyinCache = [String: String]() // comic id -> pinyin
        var library = [String: [Comic]]()
        for comic in comics {
            let pinyin = pinyinKey(comic.getName())
            pinyinCache[comic.getId()] = pinyin
            let key = String(pinyin.prefix(1)).uppercased()
            library[key, default: []].append(comic)
        }
        for key in library.keys {
            library[key]?.sort { a, b in
                let pa = pinyinCache[a.getId()] ?? ""
                let pb = pinyinCache[b.getId()] ?? ""
                return pa.localizedCaseInsensitiveCompare(pb) == .orderedAscending
            }
        }
        let titles = library.keys.sorted()
        return (sorted: library, titles: titles)
    }

    private func pinyinKey(_ chinese: String) -> String {
        let mutable = NSMutableString(string: chinese) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return mutable as String
    }

    // MARK: - Search

    @objc private func showSearch() {
        let resultsVC = TVSearchResultsController()
        resultsVC.allComics = allComics
        resultsVC.onSelect = { [weak self] comic in
            self?.showEpisodes(for: comic)
        }
        let searchController = UISearchController(searchResultsController: resultsVC)
        searchController.searchResultsUpdater = resultsVC
        let searchContainer = UISearchContainerViewController(searchController: searchController)
        searchContainer.title = "搜尋漫畫"
        navigationController?.pushViewController(searchContainer, animated: true)
    }

    // MARK: - UI Setup

    private func setUpCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let spacing: CGFloat = 48
        let sideInset: CGFloat = 80
        let availableWidth: CGFloat = 1920 - sideInset * 2 - spacing * 5
        let itemWidth = floor(availableWidth / 6)
        let itemHeight = itemWidth * 1.5 + 40
        layout.itemSize = CGSize(width: itemWidth, height: itemHeight)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: 20, left: sideInset, bottom: 40, right: sideInset)
        layout.headerReferenceSize = CGSize(width: 1920, height: 60)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TVComicCell.self, forCellWithReuseIdentifier: TVComicCell.reuseId)
        collectionView.register(TVSectionHeaderView.self,
                                forSupplementaryViewOfKind: Self.headerKind,
                                withReuseIdentifier: Self.headerId)
        view.addSubview(collectionView)
    }

    private func setUpSearchButton() {
        searchButton.addTarget(self, action: #selector(showSearch), for: .primaryActionTriggered)
        // 加到 tabBarController 的 view 上，這樣才能和 tabBar 在同一個 hierarchy
        guard let tabBarController = tabBarController else { return }
        tabBarController.view.addSubview(searchButton)

        NSLayoutConstraint.activate([
            searchButton.centerYAnchor.constraint(equalTo: tabBarController.tabBar.centerYAnchor),
            searchButton.trailingAnchor.constraint(equalTo: tabBarController.view.trailingAnchor, constant: -80),
        ])
    }

    private func setUpActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - 記住列表位置

    private func currentScrollAnchor() -> (comicId: String, offset: CGFloat)? {
        guard !sectionTitles.isEmpty else { return nil }
        let top = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        guard let indexPath = collectionView.indexPathForItem(at: CGPoint(x: 100, y: top))
                ?? collectionView.indexPathsForVisibleItems.sorted().first,
              indexPath.section < sectionTitles.count else { return nil }
        let c = comic(at: indexPath)
        let cellTop = collectionView.layoutAttributesForItem(at: indexPath)?.frame.minY ?? 0
        return (c.getId(), top - cellTop)
    }

    @objc private func saveScrollPosition() {
        guard let anchor = currentScrollAnchor() else { return }
        UserDefaults.standard.set(["comic_id": anchor.comicId, "offset": Double(anchor.offset)],
                                  forKey: Self.scrollAnchorKey)
    }

    private func restoreScrollPosition() {
        guard !didRestoreScrollPosition, view.window != nil, !sectionTitles.isEmpty else { return }
        didRestoreScrollPosition = true
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.scrollAnchorKey),
              let comicId = saved["comic_id"] as? String,
              let offset = saved["offset"] as? Double,
              let indexPath = indexPathForComic(id: comicId) else { return }
        collectionView.layoutIfNeeded()
        let inset = collectionView.adjustedContentInset
        let cellTop = collectionView.layoutAttributesForItem(at: indexPath)?.frame.minY ?? 0
        let y = cellTop + CGFloat(offset) - inset.top
        let maxY = max(collectionView.contentSize.height - collectionView.bounds.height + inset.bottom, -inset.top)
        collectionView.setContentOffset(CGPoint(x: 0, y: min(max(y, -inset.top), maxY)), animated: false)
    }

    private func indexPathForComic(id: String) -> IndexPath? {
        for (section, title) in sectionTitles.enumerated() {
            if let row = sectionedComics[title]?.firstIndex(where: { $0.getId() == id }) {
                return IndexPath(item: row, section: section)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func comic(at indexPath: IndexPath) -> Comic {
        let title = sectionTitles[indexPath.section]
        return sectionedComics[title]![indexPath.item]
    }

    // MARK: - Navigation

    private func showEpisodes(for comic: Comic) {
        let vc = TVEpisodeListViewController()
        vc.currentComic = comic
        vc.title = comic.getName()
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension TVComicGridViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sectionTitles.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section < sectionTitles.count else { return 0 }
        return sectionedComics[sectionTitles[section]]?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TVComicCell.reuseId, for: indexPath) as! TVComicCell
        cell.configure(with: comic(at: indexPath), modifier: refererModifier)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                         viewForSupplementaryElementOfKind kind: String,
                         at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: Self.headerId, for: indexPath) as! TVSectionHeaderView
        header.titleLabel.text = sectionTitles[indexPath.section]
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        showEpisodes(for: comic(at: indexPath))
    }
}

// MARK: - TVComicCell

class TVComicCell: UICollectionViewCell {

    static let reuseId = "TVComicCell"

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    /// focus 時的陰影與放大效果由系統處理，這裡只需要加上 adjustsImageWhenAncestorFocused

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.adjustsImageWhenAncestorFocused = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 26, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 1.5),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with comic: Comic, modifier: ImageDownloadRequestModifier) {
        titleLabel.text = comic.getName()
        imageView.kf.cancelDownloadTask()
        if let urlStr = comic.getSmallIconUrl(), let url = URL(string: urlStr) {
            imageView.kf.setImage(with: url,
                                  placeholder: UIImage(named: "comic_place_holder"),
                                  options: [.transition(.fade(0.3)),
                                            .requestModifier(modifier),
                                            .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(2)))])
        } else {
            imageView.image = UIImage(named: "comic_place_holder")
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        titleLabel.text = nil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations({
            if self.isFocused {
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self.titleLabel.textColor = .black
            } else {
                self.transform = .identity
                self.titleLabel.textColor = .white
            }
        })
    }
}

// MARK: - TVSectionHeaderView

class TVSectionHeaderView: UICollectionReusableView {

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 38)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 80),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - TVSearchResultsController

class TVSearchResultsController: UIViewController, UISearchResultsUpdating {

    var allComics = [Comic]()
    var onSelect: ((Comic) -> Void)?

    private var filterComics = [Comic]()
    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
        if query.isEmpty {
            filterComics = []
        } else {
            filterComics = allComics.filter { $0.getName().localizedCaseInsensitiveContains(query) }
        }
        tableView.reloadData()
    }
}

extension TVSearchResultsController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filterComics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = filterComics[indexPath.row].getName()
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let comic = filterComics[indexPath.row]
        dismiss(animated: true) { [weak self] in
            self?.onSelect?(comic)
        }
    }
}
