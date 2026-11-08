# Boxtube for iPhone and Mac — implementation plan

Native Swift 6 + SwiftUI, built from the redesign canvas. One multiplatform app target (iOS 27 / macOS 27), one local Swift package for shared code, one widget extension.

## Layout

```
apple/
  project.yml                 XcodeGen spec (generate with `xcodegen`)
  Config/
    Base.xcconfig             team, bundle ids, deployment targets
    Secrets.example.xcconfig  copy to Secrets.xcconfig (git-ignored) and add YOUTUBE_API_KEY
  Packages/BoxtubeKit/        local Swift package
    BoxtubeCore               models, API client, RSS, cache (GRDB), chapters, time-box solver
    BoxtubeUI                 design tokens, glass, thumbnails (Nuke), island, shared components
    BoxtubePlayer             one reusable WKWebView running the YouTube IFrame Player API
  Boxtube/                    app target
    App/                      entry point, AppModel, routing
    iOS/                      iPhone screens + island
    macOS/                    sidebar shell, command palette, menu bar player, floating player
    Shared/                   screens used on both (Watch, Music, Notes, Time box)
  BoxtubeWidgets/             Live Activity + Dynamic Island + lock-screen widgets
```

## Data

| Need | Source | Quota |
|---|---|---|
| Subscriptions feed | Channel RSS `youtube.com/feeds/videos.xml?channel_id=` | none |
| Video details, durations, stats | Data API `videos.list` (batched 50 ids) | 1 unit / 50 |
| Home / topics | Data API `videos.list chart=mostPopular` + category | 1 |
| Shorts | Data API `playlistItems` on `UUSH…` playlists of subscribed channels | 1 |
| Search | Data API `search.list` (only when the user types) | 100 |
| Music | `mostPopular` with `videoCategoryId=10`, local music playlists | 1 |
| Library (subs, playlists, watch later, history, notes, likes) | Local SQLite via GRDB | none |

Everything fetched is cached in SQLite with a freshness time, so the app opens instantly offline and spends almost no quota. Google sign-in (to import real subscriptions/playlists) is a later phase once an iOS OAuth client ID exists.

## Player

A single `WKWebView` created once (`PlayerEngine`) loads a local HTML page with the IFrame Player API (`controls=0`), and is re-parented into whichever view shows video. Swift talks to it through `evaluateJavaScript` and a `WKScriptMessageHandler` that streams time/state ~4×/s. Everything time-based (island scrubber, chapters, notes, Live Activity, SharePlay) reads `PlayerEngine.state`. Foreground only, no audio-only mode (YouTube terms).

## Phases

1. **Foundation**: XcodeGen project, package, design tokens (coral `#FF5A4E`, ink, glass), Bricolage-style display font fallback to SF Rounded/system, thumbnail art fallback, app icon from the canvas.
2. **Core**: models, API client, RSS parser, GRDB store + migrations, chapter parser, ISO-8601 durations, time-box solver, color extraction.
3. **Player**: `PlayerEngine`, `PlayerSurface`, custom controls, chapter scrubber.
4. **iPhone**: island (5 tabs + search orb + mini player), Home, Shorts, Subscriptions, Playlists, You, Watch.
5. **Mac**: sidebar shell, Home, Watch, menu bar extra, keyboard shortcuts, command palette (⌘K), floating player window.
6. **Ideas**: 01 time boxes, 02 decaying watch later, 03 calm mode, 04 island scrub / chapter ring / command panel, 05 Live Activity + Dynamic Island + widgets, 06 skim mode, 07 timestamped notes + markdown export, 08 keyboard first, 09 colors from the video, 10 watch together (SharePlay).
7. **Music mode**: Videos/Music switch, music home, now playing, library, Mac music layout, "Continue in YouTube Music" hand-off.
8. **Verify**: build both platforms, drive every screen in the iOS Simulator, run the Mac app, install on the iPhone.

## Known limits

- Personal (free) signing team: apps expire after 7 days; iCloud/CloudKit and some entitlements are unavailable, so notes sync stays local for now.
- Lyrics need a licensed provider; the UI shows a placeholder.
- YouTube terms: embedded player only, foreground playback, keep player branding visible.
