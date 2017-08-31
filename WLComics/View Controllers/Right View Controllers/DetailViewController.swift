//
//  DetailViewController.swift
//  WLComics
//
//  Created by Webber Lai on 2017/7/26.
//  Copyright © 2017年 webberlai. All rights reserved.
//

import UIKit

@objc protocol DetailViewControllerDelegate: NSObjectProtocol {
    func sliderImageTapped(index: Int)
}

class DetailViewController: UIViewController,CPSliderDelegate{

    @IBOutlet weak var detailDescriptionLabel: UILabel!
    
    var comicImages = Array<String>()
    
    @IBOutlet weak var imgSlider : CPImageSlider!

    weak var delegate: DetailViewControllerDelegate?
    
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
        imgSlider.enablePageIndicator = false
        if UIDevice.current.model.description == "iPhone"{
            navigationItem.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .cancel , target: self, action: #selector(close))
        }
    }
    
    func close(){
        self.dismiss(animated: true, completion: nil)
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
        delegate?.sliderImageTapped(index: index)
    }
}

