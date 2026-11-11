# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- **Open `WLComics.xcworkspace`** (not `.xcodeproj`) — CocoaPods workspace
- Install dependencies: `pod install` at the repo root (where `Podfile` is). Pods/ is tracked in git
- Build target: `WLComics` (iOS 15.0+; Xcode 27 no longer supports iOS 14 deployment targets — keep `Podfile` `platform :ios` and its `post_install` override in sync), supports iPhone and iPad. Product name is `看漫畫`; `PRODUCT_MODULE_NAME = WLComics` is set explicitly so tests can `@testable import WLComics`
- Unit tests: `WLComicsTests` target (XCTest, deployment target 15.6), files in `WLComicsTests/` (synchronized folder — new files are picked up automatically). Run with ⌘U
  - `UpdateTracker` / `ReadingModeStore` expose their logic as static pure functions (`applying`, `markingSeen`, `merged`, `trimmed`, `mode(in:for:)`…); tests call those and never touch UserDefaults / iCloud KVS
  - `SDKParserTests` parses saved 8comic pages in `WLComicsTests/Fixtures/` — run after editing `Comic8SDK`'s `Parser` / `JSnview`
  - `SDKLiveSiteTests` hits the real site to detect redesigns; skipped unless the scheme sets env var `WLCOMICS_LIVE_TESTS=1`
- Adding a target in Xcode 26 bumps `objectVersion` to 70, which CocoaPods (xcodeproj 1.27) rejects — change it to 77 in `project.pbxproj` before `pod install`

## Architecture

**Classical MVC with UISplitViewController** — iPad shows master (left) + detail (right) simultaneously; iPhone uses modal navigation.

### View Controller Flow

```
TabBarController
├── Tab 1: MasterViewController (all comics, A-Z pinyin index)
│   └── ComicEpisodesViewController (episode list for one comic)
│       ├── iPad: EpisodeDetailViewController (left) + DetailViewController (right, via SplitVC)
│       └── iPhone: DetailViewController (modal, full-screen reader)
└── Tab 2: FavoriteTableViewController (bookmarked comics)
    └── ComicEpisodesViewController (same flow as above)
```

### Key Singletons & Utilities

- **`WLComics.sharedInstance()`** — app-level wrapper around `R8Comic` (in `Comic8SDK/`). Handles episode loading, search API, Kingfisher referer headers.
- **`FavoriteComics`** — static utility for favorites CRUD via `MyFavoritesComics.plist`, synced via iCloud key-value store (`startCloudSync()` in AppDelegate).

### Image Loading (CPImageSlider)

`CPImageSlider` is a custom `UIScrollView`-based image viewer in `3rd Image Slider/`. Key behaviors:
- **Lazy loading**: only downloads current page ±2 pages (`prefetchRange`), tracked by `loadedIndices`
- **Referer header required**: 8comic.com blocks requests without proper `Referer` — always use `WLComics.buildDownloadEpisodeHeader(episodeUrl)`
- **`episodeUrl` must be set before `images`**: use `DetailViewController.updateEpisode(url:images:)` to set both atomically on main queue
- **Non-circular mode** (`allowCircular = false`): swipe past last/first page triggers `onSwipePastLastPage`/`onSwipePastFirstPage` callbacks for episode navigation
- When switching episodes, call `cancelAllDownloads()` before setting new images
- **Spread mode** (`isSpreadMode`, non-circular only): two pages per screen, earlier page on the right (manga order). `currentIndex` stays a page index aligned to the spread's first page; scroll offsets are in spreads. `DetailViewController` enables it only when `isiOSAppOnMac` and the slider is landscape

### Data Flow for Comic Reading

```
loadEpisodeDetail(episode) → callback (may be background thread)
  → episode.setUpPages() → JS evaluation extracts image URLs
  → updateEpisode(url:, images:) → main queue
    → CPImageSlider.episodeUrl = url
    → CPImageSlider.images = urls → addImagesOnScrollView() → loadVisibleImages()
```

### Comic8SDK (`WLComics/Comic8SDK/`, vendored)

8comic.com scraper, originally the Swift8ComicSDK CocoaPod (2.0.6, MIT). Upstream is unmaintained, so the source now lives in the app target and is edited directly — no `import` needed.
- **`Parser.swift`** — HTML parsing. `comicDetail` reads the 2026 page layout: episodes from `cview(...)`, author `item-info-author`, update date `item-info-date`, description the line after `item_info_detail`
- **`JSnview.swift`** — JS evaluation for image URLs; handles both old (`var cs='...'`) and new (`.src=unescape(...)`) website formats
- **`StringUtility.swift`** — `dataToStringBig5` / `dataToStringGB2312` decode UTF-8 first (the site is UTF-8 now) and fall back to the legacy encoding
- **`R8Comic.swift`** — main class; `loadEpisodeDetail` callback may run on background thread
- **`Episode.swift`** — has `public init()` so the app can rebuild `Episode` objects from download records

### Data Persistence

- **`AllComics.plist`** — bundled comic database (~10800 entries). Copied to Documents on app version change. Primary source for comic list.
- **`MyFavoritesComics.plist`** — favorites, stored in Documents, mirrored to `NSUbiquitousKeyValueStore` key `favorite_list`
- **Reading progress** — `ReadingProgress` stores last episode/page per comic in UserDefaults + iCloud KVS key `reading_progress`; episode URLs are compared via `normalizedEpisodeUrl` (relative before load, absolute after)
- **Offline downloads** — `DownloadManager` saves pages to `Application Support/Downloads/<comicId>/<episode>/` with a `manifest.json` per comic (file names only, never absolute paths); excluded from backup; deletion is manual only. Readers check `localPageURLs` before hitting the network. The 已下載 tab (`DownloadsViewController`) is appended to the tab bar in `SceneDelegate` and opens `ComicEpisodesViewController` (storyboard ID) with `offlineMode = true`
- **`MasterViewController.favoriteIds`** — in-memory `Set<String>` cache of favorite comic IDs, rebuilt in `viewWillAppear`

## Apple TV (`WLTVComics/`)

- Scheme / target `wltvcomics`, tvOS 26.2+ (`PRODUCT_MODULE_NAME = WLTVComics`). `WLTVComics/` is a synchronized folder — new files join the target automatically. Pods: only Kingfisher (`Podfile` `target 'wltvcomics'`, tvOS 16.0)
- **Shared with iOS** (listed explicitly in the target, not via the folder): `Comic8SDK/*`, `WLComics.swift`, `FavoriteComics.swift`, `SwiftyPlistManager.swift`, `ReadingProgress.swift`, `ReadingModeStore.swift`, `VerticalReaderView.swift`. Edits there affect both apps; use `#if os(tvOS)` for platform differences
- **Storage**: tvOS Documents is restricted, so `SwiftyPlistManager` and `TVAppDelegate` use Caches for the plists. No offline downloads on TV
- **Flow**: storyboard `TabBarController` → nav (bar hidden) → `TVComicGridViewController` / `TVFavoriteGridViewController` → push `TVEpisodeListViewController` (shows the nav bar for 繼續閱讀) → present `TVReaderViewController`

### TVReaderViewController

- Paged mode always shows two pages via `TVSpreadView`: `currentPage` is aligned to even (spread's first page), arrows step by 2, odd last page leaves the other half blank. Right arrow = next spread in both directions
- Modes via play/pause or long-press select → menu: 日漫翻頁 (first page on the right), 美漫翻頁 (first page on the left), 韓漫直式 (`VerticalReaderView`). Paged/vertical uses the shared `ReadingModeStore`; left-to-right is TV-only, local UserDefaults key `tv_left_to_right_comics`
- No page-number overlay — only the episode name (top-left) and mode hint (top-right)

### tvOS Pitfalls

- **Presses**: overriding `pressesBegan` without `super` requires also swallowing the same types in `pressesEnded` / `pressesChanged` / `pressesCancelled`, otherwise Menu's end event reaches the navigation controller and pops while the reader dismisses (black screen)
- **Focus**: if a screen has nothing focusable, Menu goes straight to the root and the app exits to the Home screen. `TVEpisodeListViewController` uses an invisible `TVFocusAnchorView` while the list is empty (the user rejected a visible loading/retry row because it flashes). The grid's search button lives on `tabBarController.view`, so it is hidden in `viewWillDisappear`
- **Empty episode lists**: some comics' detail pages (e.g. 24702 / 24703) return HTTP 200 with a 0-byte body — a site problem, intentionally not worked around. `loadComicDetail` never calls back on failure, hence the 20 s spinner timeout
- **iOS-only UIKit APIs that break the tvOS build**: `UISearchBar.searchTextField`, `secondarySystemBackground` / `systemGroupedBackground` colors, `UITableView.separatorStyle` / `separatorColor`. Build the `wltvcomics` scheme after UI changes

## Key Dependencies

| Pod | Purpose |
|-----|---------|
| Kingfisher | Image downloading/caching with custom request modifiers |
| SVProgressHUD | Loading spinner |

## Common Pitfalls

- **Thread safety**: `loadEpisodeDetail` callback can be on a background thread. Always dispatch UI updates to main queue.
- **Chinese pinyin sorting**: `CFStringTransform` is slow for 10000+ entries — always run `buildComicLibrary` on background queue.
- **Image download failures**: missing/wrong `Referer` header causes 8comic.com to reject requests silently.
- **Xcode resets `objectVersion`**: Xcode may save `project.pbxproj` back to `objectVersion = 70`; set it to 77 again before each `pod install`.
