//
//  TVFavoriteGridViewController.swift
//  WLTVComics
//
//  收藏漫畫列表 — tvOS 用 UICollectionView 海報網格
//

import UIKit
import Kingfisher

class TVFavoriteGridViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var favorites = [NSMutableDictionary]()
    private let emptyLabel = UILabel()

    private let refererModifier = AnyModifier { request in
        var r = request
        r.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        return r
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.isNavigationBarHidden = true

        setUpCollectionView()
        setUpEmptyLabel()

        NotificationCenter.default.addObserver(self, selector: #selector(favoritesDidChange),
                                               name: FavoriteComics.didChangeNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadFavorites()
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
        layout.sectionInset = UIEdgeInsets(top: 40, left: sideInset, bottom: 40, right: sideInset)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TVComicCell.self, forCellWithReuseIdentifier: TVComicCell.reuseId)
        view.addSubview(collectionView)
    }

    private func setUpEmptyLabel() {
        emptyLabel.text = "還沒有收藏任何漫畫"
        emptyLabel.font = .systemFont(ofSize: 38)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Data

    @objc private func favoritesDidChange() {
        reloadFavorites()
    }

    private func reloadFavorites() {
        favorites = FavoriteComics.listAllFavorite()
        emptyLabel.isHidden = !favorites.isEmpty
        collectionView.reloadData()
    }

    private func comicForItem(at index: Int) -> Comic? {
        guard index < favorites.count,
              let comicId = favorites[index].object(forKey: "comic_id") as? String,
              let name = favorites[index].object(forKey: "name") as? String else { return nil }
        let comic = WLComics.sharedInstance().getR8Comic().generatorFakeComic(comicId, name: name)
        let r8comic = WLComics.sharedInstance().getR8Comic()
        let iconUrl = favorites[index].object(forKey: "icon_url") as? String ?? r8comic.getComicSmallIconUrl(comicId)
        comic.setSmallIconUrl(iconUrl)
        comic.setIconUrl(r8comic.getComicIconUrl(comicId))
        return comic
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension TVFavoriteGridViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return favorites.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TVComicCell.reuseId, for: indexPath) as! TVComicCell
        if let comic = comicForItem(at: indexPath.item) {
            cell.configure(with: comic, modifier: refererModifier)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let comic = comicForItem(at: indexPath.item) else { return }
        let vc = TVEpisodeListViewController()
        vc.currentComic = comic
        vc.title = comic.getName()
        navigationController?.pushViewController(vc, animated: true)
    }
}
