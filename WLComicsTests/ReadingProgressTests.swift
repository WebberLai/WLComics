//
//  ReadingProgressTests.swift
//  WLComicsTests
//
//  Created by Roca Developer on 2026/10/7.
//  Copyright © 2026 webberlai. All rights reserved.
//

import XCTest
@testable import WLComics

final class ReadingProgressTests: XCTestCase {

    func testNormalizedEpisodeUrlStripsPrefix() {
        let full = "https://www.8comic.com/view/123.html?ch=5"
        XCTAssertEqual(ReadingProgress.normalizedEpisodeUrl(full), "123.html?ch=5")
    }

    func testNormalizedEpisodeUrlKeepsRelativeUrl() {
        XCTAssertEqual(ReadingProgress.normalizedEpisodeUrl("123.html?ch=5"), "123.html?ch=5")
    }

    /// 載入前後的兩種寫法要視為同一集
    func testNormalizedEpisodeUrlMatchesBothForms() {
        let relative = "/view/123.html?ch=5"
        let absolute = "https://www.8comic.com/view/123.html?ch=5"
        XCTAssertEqual(ReadingProgress.normalizedEpisodeUrl(relative),
                       ReadingProgress.normalizedEpisodeUrl(absolute))
    }
}
