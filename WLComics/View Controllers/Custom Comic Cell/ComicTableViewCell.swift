//
//  ComicTableViewCell.swift
//  WLComics
//
//  Created by Roca Developer on 2017/8/31.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit

class ComicTableViewCell: UITableViewCell {

    @IBOutlet weak var coverImageView : UIImageView!
    @IBOutlet weak var comicNametextLabel: UILabel!
    @IBOutlet weak var favoriteBtn : UIButton!
    
    var isFavorite : Bool = false
    
    var favoriteButtonPress : ((UIButton) -> Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
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
