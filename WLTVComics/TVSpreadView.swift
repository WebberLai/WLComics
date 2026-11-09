//
//  TVSpreadView.swift
//  WLTVComics
//
//  一次顯示兩頁（跨頁）。兩張圖等高、在中線貼齊，整組置中縮放到放得進畫面。
//  日漫（右翻左）較前的頁放右邊；美漫（左翻右）較前的頁放左邊。
//

import UIKit
import Kingfisher

class TVSpreadView: UIView {

    /// true：日漫順序，第一頁在右；false：美漫順序，第一頁在左
    var isRightToLeft = true {
        didSet { if oldValue != isRightToLeft { setNeedsLayout() } }
    }

    /// 圖還沒下載完時暫用的寬高比（一般單頁漫畫約 0.7）
    private static let placeholderAspect: CGFloat = 0.7

    private let firstImageView = UIImageView()
    private let secondImageView = UIImageView()
    private var hasSecondPage = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        for iv in [firstImageView, secondImageView] {
            iv.contentMode = .scaleAspectFit
            iv.backgroundColor = .black
            iv.clipsToBounds = true
            addSubview(iv)
        }
    }

    /// second 為 nil 表示只剩一頁（奇數頁的最後一頁），另一半留空白
    func show(first: URL?, second: URL?, options: KingfisherOptionsInfo) {
        cancelDownloads()
        firstImageView.image = nil
        secondImageView.image = nil
        hasSecondPage = second != nil
        secondImageView.isHidden = !hasSecondPage

        if let first = first {
            firstImageView.kf.setImage(with: first, options: options) { [weak self] _ in
                self?.setNeedsLayout()
            }
        }
        if let second = second {
            secondImageView.kf.setImage(with: second, options: options) { [weak self] _ in
                self?.setNeedsLayout()
            }
        }
        setNeedsLayout()
    }

    func cancelDownloads() {
        firstImageView.kf.cancelDownloadTask()
        secondImageView.kf.cancelDownloadTask()
    }

    private func aspect(of imageView: UIImageView, fallback: CGFloat) -> CGFloat {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return fallback }
        return size.width / size.height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let firstAspect = aspect(of: firstImageView, fallback: TVSpreadView.placeholderAspect)
        // 另一張還沒到時，先假設和已到的那張一樣比例，避免載入完跳動太大。
        // 最後一頁落單時第二格留空白，第一頁仍待在原本的位置（日漫在右、美漫在左）
        let secondAspect = hasSecondPage
            ? aspect(of: secondImageView, fallback: firstImageView.image == nil ? TVSpreadView.placeholderAspect : firstAspect)
            : firstAspect

        // 依畫面上由左到右的順序排
        let leftIsFirst = !isRightToLeft
        let aspects = leftIsFirst ? [firstAspect, secondAspect] : [secondAspect, firstAspect]
        let frames = fitted(aspects: aspects, in: bounds)
        if leftIsFirst {
            firstImageView.frame = frames[0]
            secondImageView.frame = frames[1]
        } else {
            secondImageView.frame = frames[0]
            firstImageView.frame = frames[1]
        }
    }

    /// 由左到右並排、等高、整組置中並縮放到放得進 bounds
    private func fitted(aspects: [CGFloat], in bounds: CGRect) -> [CGRect] {
        var height = bounds.height
        let totalWidth = aspects.reduce(0) { $0 + $1 * height }
        if totalWidth > bounds.width {
            height *= bounds.width / totalWidth
        }
        let widths = aspects.map { $0 * height }
        var x = bounds.midX - widths.reduce(0, +) / 2
        let y = bounds.midY - height / 2
        return widths.map { w in
            defer { x += w }
            return CGRect(x: x, y: y, width: w, height: height).integral
        }
    }
}
