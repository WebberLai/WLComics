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
    private let searchController = UISearchController(searchResultsController: nil)

    private var allComics = [Comic]()
    private var displayedComics = [Comic]()
    private var isSearching = false

    /// 8comic 會擋掉沒有 Referer 的圖片請求
    private let refererModifier = AnyModifier { request in
        var r = request
        r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        return r
    }

    private let activityIndicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "漫畫列表"
        view.backgroundColor = .black

        setUpCollectionView()
        setUpSearchController()
        setUpActivityIndicator()

        activityIndicator.startAnimating()
        WLComics.sharedInstance().loadAllComics { [weak self] comics in
            guard let self = self else { return }
            self.allComics = comics
            self.displayedComics = comics
            self.activityIndicator.stopAnimating()
            self.collectionView.reloadData()

            // 背景更新漫畫列表
            self.refreshComicsFromWeb()
        }
    }

    private func refreshComicsFromWeb() {
        WLComics.sharedInstance().refreshComicsFromWeb { [weak self] updatedComics in
            guard let self = self, updatedComics.count > self.allComics.count else { return }
            self.allComics = updatedComics
            if !self.isSearching {
                self.displayedComics = updatedComics
                self.collectionView.reloadData()
            }
        }
    }

    // MARK: - UI Setup

    private func setUpCollectionView() {
        let layout = UICollectionViewFlowLayout()
        // tvOS 大螢幕，每排放 6 張海報
        let spacing: CGFloat = 48
        let sideInset: CGFloat = 80
        let availableWidth = UIScreen.main.bounds.width - sideInset * 2 - spacing * 5
        let itemWidth = floor(availableWidth / 6)
        let itemHeight = itemWidth * 1.5 + 40 // 海報 + 標題
        layout.itemSize = CGSize(width: itemWidth, height: itemHeight)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: 40, left: sideInset, bottom: 40, right: sideInset)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TVComicCell.self, forCellWithReuseIdentifier: TVComicCell.reuseId)
        view.addSubview(collectionView)
    }

    private func setUpSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜尋漫畫名稱"
        navigationItem.searchController = searchController
        definesPresentationContext = true
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

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return displayedComics.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TVComicCell.reuseId, for: indexPath) as! TVComicCell
        let comic = displayedComics[indexPath.item]
        cell.configure(with: comic, modifier: refererModifier)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        showEpisodes(for: displayedComics[indexPath.item])
    }
}

// MARK: - Search

extension TVComicGridViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard let text = searchController.searchBar.text, !text.isEmpty else {
            isSearching = false
            displayedComics = allComics
            collectionView.reloadData()
            return
        }
        isSearching = true
        displayedComics = allComics.filter {
            ($0.getName() as NSString).range(of: text, options: .caseInsensitive).location != NSNotFound
        }
        collectionView.reloadData()
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
            self.titleLabel.textColor = self.isFocused ? .black : .white
        })
    }
}
