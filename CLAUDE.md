# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- **Open `WLComics.xcworkspace`** (not `.xcodeproj`) — CocoaPods workspace
- Install/update dependencies: `cd WLComics && pod install`
- Build target: `WLComics` (iOS 14.0+), supports iPhone and iPad
- No test targets exist in this project

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

- **`WLComics.sharedInstance()`** — app-level wrapper around `R8Comic` SDK. Handles episode loading, search API, Kingfisher referer headers.
- **`FavoriteComics`** — static utility for favorites CRUD via `MyFavoritesComics.plist`, synced to Dropbox.

### Image Loading (CPImageSlider)

`CPImageSlider` is a custom `UIScrollView`-based image viewer in `3rd Image Slider/`. Key behaviors:
- **Lazy loading**: only downloads current page ±2 pages (`prefetchRange`), tracked by `loadedIndices`
- **Referer header required**: 8comic.com blocks requests without proper `Referer` — always use `WLComics.buildDownloadEpisodeHeader(episodeUrl)`
- **`episodeUrl` must be set before `images`**: use `DetailViewController.updateEpisode(url:images:)` to set both atomically on main queue
- **Non-circular mode** (`allowCircular = false`): swipe past last/first page triggers `onSwipePastLastPage`/`onSwipePastFirstPage` callbacks for episode navigation
- When switching episodes, call `cancelAllDownloads()` before setting new images

### Data Flow for Comic Reading

```
loadEpisodeDetail(episode) → callback (may be background thread)
  → episode.setUpPages() → JS evaluation extracts image URLs
  → updateEpisode(url:, images:) → main queue
    → CPImageSlider.episodeUrl = url
    → CPImageSlider.images = urls → addImagesOnScrollView() → loadVisibleImages()
```

### Swift8ComicSDK (CocoaPod, source in `Pods/`)

External SDK that scrapes 8comic.com. Locally modified files in Pods/:
- **`Parser.swift`** — HTML parsing with guards for variable-length data arrays
- **`JSnview.swift`** — JS evaluation for image URLs; handles both old (`var cs='...'`) and new (`.src=unescape(...)`) website formats
- **`R8Comic.swift`** — main SDK class; `loadEpisodeDetail` callback may run on background thread

### Data Persistence

- **`AllComics.plist`** — bundled comic database (~10800 entries). Copied to Documents on app version change. Primary source for comic list.
- **`MyFavoritesComics.plist`** — favorites, stored in Documents, synced to Dropbox via SwiftyDropbox
- **`MasterViewController.favoriteIds`** — in-memory `Set<String>` cache of favorite comic IDs, rebuilt in `viewWillAppear`

## Key Dependencies

| Pod | Purpose |
|-----|---------|
| Swift8ComicSDK | 8comic.com scraper (git-based, locally patched) |
| Kingfisher | Image downloading/caching with custom request modifiers |
| SwiftyDropbox | Favorites cloud sync |
| SVProgressHUD | Loading spinner |

## Common Pitfalls

- **Thread safety**: `loadEpisodeDetail` callback can be on a background thread. Always dispatch UI updates to main queue.
- **Chinese pinyin sorting**: `CFStringTransform` is slow for 10000+ entries — always run `buildComicLibrary` on background queue.
- **Image download failures**: missing/wrong `Referer` header causes 8comic.com to reject requests silently.
- **Pod modifications**: SDK bugs are fixed directly in `Pods/Swift8ComicSDK/` — these changes are lost on `pod install`. Consider forking the SDK.
