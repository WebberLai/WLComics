//
//  DetailViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/26.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit

class DetailViewController: UIViewController,CPSliderDelegate{

    @IBOutlet weak var detailDescriptionLabel: UILabel!
    
    var comicImages = Array<String>()
    
    @IBOutlet weak var imgSlider : CPImageSlider!

    var hidden = false {
        didSet {
            if let nav = navigationController {
                nav.setNavigationBarHidden(hidden, animated: true)
                nav.setToolbarHidden(hidden, animated: true)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        imgSlider.delegate = self
        imgSlider.enableSwipe = true
        imgSlider.allowCircular = false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.hidesBarsOnTap = true
    }
    
    //設定每集漫畫的root網址
    func setEpisodeUrl(_ url : String){
        self.imgSlider.episodeUrl = url
    }
    
    func updateImages(imgs : Array<String>){
        DispatchQueue.main.async {
            self.imgSlider.images = imgs
        }
    }
    
    func sliderImageTapped(slider: CPImageSlider, index: Int) {
        hidden = !hidden
        self.navigationController?.navigationBar.isHidden = hidden
    }
}

