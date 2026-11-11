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
    private let emptyHintLabel = UILabel()
    private let emptyIconView = UIImageView(image: UIImage(systemName: "books.vertical"))

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
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadFavorites()
    }

    // MARK: - UI Setup

    private func setUpCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let spacing: CGFloat = 42
        let sideInset: CGFloat = 76
        let columns: CGFloat = 6
        let availableWidth = max(0, view.bounds.width - sideInset * 2 - spacing * (columns - 1))
        let itemWidth = floor(availableWidth / columns)
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
        emptyLabel.text = "收藏你的下一本漫畫"
        emptyLabel.font = .systemFont(ofSize: 36, weight: .semibold)
        emptyLabel.textColor = .white
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        emptyHintLabel.text = "在漫畫列表選取封面，加入個人書架。"
        emptyHintLabel.font = .systemFont(ofSize: 24, weight: .regular)
        emptyHintLabel.textColor = .secondaryLabel
        emptyHintLabel.textAlignment = .center
        emptyHintLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyHintLabel.isHidden = true
        emptyIconView.tintColor = UIColor(red: 0.95, green: 0.38, blue: 0.27, alpha: 1)
        emptyIconView.contentMode = .scaleAspectFit
        emptyIconView.translatesAutoresizingMaskIntoConstraints = false
        emptyIconView.isHidden = true
        let stack = UIStackView(arrangedSubviews: [emptyIconView, emptyLabel, emptyHintLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyIconView.widthAnchor.constraint(equalToConstant: 72),
            emptyIconView.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    // MARK: - Data

    @objc private func favoritesDidChange() {
        reloadFavorites()
    }

    private func reloadFavorites() {
        favorites = FavoriteComics.listAllFavorite()
        emptyLabel.isHidden = !favorites.isEmpty
        emptyHintLabel.isHidden = !favorites.isEmpty
        emptyIconView.isHidden = !favorites.isEmpty
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
