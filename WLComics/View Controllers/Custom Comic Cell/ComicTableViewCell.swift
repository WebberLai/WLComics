//
//  ComicTableViewCell.swift
//  WLComics
//
//  Created by Webber Lai on 2017/8/31.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit

class ComicTableViewCell: UITableViewCell {

    @IBOutlet weak var coverImageView : UIImageView!
    @IBOutlet weak var comicNametextLabel: UILabel!
    @IBOutlet weak var favoriteBtn : UIButton!
        
    var favoriteButtonPress : ((UIButton) -> Void)?

    /// 收藏列表標示有新集數；預設隱藏，放在愛心按鈕的位置（收藏列表會隱藏愛心）
    private let updateBadgeLabel: UILabel = {
        let label = UILabel()
        label.text = "NEW"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .systemRed
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    var showsUpdateBadge: Bool {
        get { return !updateBadgeLabel.isHidden }
        set { updateBadgeLabel.isHidden = !newValue }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // 空心愛心（dislike）是 template 圖，用系統次要文字色，深色模式下才看得到
        favoriteBtn.tintColor = .secondaryLabel
        // iPad 左欄較窄，長名稱單行會被截成「…」；列高有 100pt，最多換三行
        comicNametextLabel.numberOfLines = 3
        comicNametextLabel.lineBreakMode = .byTruncatingTail

        contentView.addSubview(updateBadgeLabel)
        NSLayoutConstraint.activate([
            updateBadgeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            updateBadgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            updateBadgeLabel.widthAnchor.constraint(equalToConstant: 36),
            updateBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        showsUpdateBadge = false
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        // Configure the view for the selected state
    }
    
    @IBAction func favoriteBtnToggle(_ sender : UIButton){
        favoriteBtn = sender
        favoriteButtonPress?(sender)
    }
}
