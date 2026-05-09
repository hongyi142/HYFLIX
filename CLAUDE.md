# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HYFLIX is a Netflix-style streaming app built with Flutter. It aggregates content from multiple Chinese VOD provider APIs, enriches metadata via TMDB, and plays m3u8 streams using media_kit. Targets Android, iOS, macOS, Windows, and Web.

## Build & Run Commands

```bash
# Run the app (default device)
flutter run

# Build for specific platforms
flutter build apk
flutter build ios
flutter build macos
flutter build windows
flutter build web

# Analysis and tests
flutter analyze
flutter test
flutter test test/widget_test.dart  # single test file
flutter pub get                      # install dependencies
flutter pub upgrade --major-versions  # upgrade deps
```

## Architecture

### Data Flow

```
TMDB API ──→ TmdbService (metadata, search, trending)
                  │
                  ▼
VOD Provider APIs ──→ ApiService (5 sources: Hong Niu, FFZY, BFZY, LZ, HW)
                  │         │
                  │    matchTmdbToProvider() — fuzzy title matching with scoring
                  │         │
                  │         ▼
                  │    ContentModel (unified content model)
                  │
                  ▼
            SplashPage (parallel fetch of 7 categories)
                  │
                  ▼
            HomePage (hero carousel + horizontal shelves)
```

### Key Services

| Service | Role |
|---------|------|
| `ApiService` | Fetches from VOD providers, matches TMDB results to provider content. Singleton with multi-source support (`VideoSource` + `_activeBaseUrl`). |
| `TmdbService` | TMDB API wrapper. Provides trending/discover/search with language support (en-US, zh-CN). Caches results in-memory. |
| `AuthService` | Firebase Auth via REST API (email/password + Google sign-in). Token refresh, profile updates. |
| `FirestoreService` | Firebase Realtime Database (despite the name). Stores user profiles, watch history, favourites, preferences via REST. |
| `UserService` | Thin wrapper over FirestoreService for profile, watch history, favourites, preferences. |
| `WatchlistService` | Local watchlists using SharedPreferences. ChangeNotifier pattern. |
| `DownloadService` | Downloads m3u8 streams segment-by-segment with AES-128 decryption. ChangeNotifier pattern. |
| `SubtitleService` | Subtitle search via SubDL + OpenSubtitles APIs. Merges results, handles ZIP/GZIP extraction. |

### Content Matching Pipeline

This is the most complex part of the codebase. When the splash screen loads:

1. `SplashPage._loadData()` fires 7 `fetchMatched*` calls in parallel via `Future.wait`
2. Each calls `ApiService._matchTmdbShelf()` which:
   - Fetches TMDB results (oversampled at `count * 3`)
   - Processes in batches of 5 via `Future.wait` (batches are sequential)
   - For each TMDB item, `matchTmdbToProvider()` searches the VOD provider by title and scores candidates using `_scoreRawMatch()`
   - Score considers: title match, year match, media type, genre, language/region metadata
   - If score < 35, falls back to `TmdbService.findChineseTitles()` for Chinese title lookup via TMDB translations API
   - Groups multi-season content via `_groupSeasons()`
3. Results are cached in SharedPreferences with 12-hour TTL

### Pages & Navigation

- `SplashPage` → loads all content → pushes `HomePage` (or `AuthPage` if not logged in)
- `HomePage` → hero carousel + 7 horizontal shelves + bottom nav (phone) or desktop nav
- `DetailPage` → modal dialog showing content info, episodes, source picker, cast, subtitles
- `VideoPlayerScreen` → media_kit player with custom controls, episode/subtitle panels, skip intro
- `BrowsePage` → paginated grid with type/area/year/sort filters
- `SearchPage` → searches all 5 sources in parallel with English→Chinese title translation
- `ProfilePage` → user stats, watch history, favourites
- `SettingsPage` → language (EN/ZH), default source, account management, clear history
- `MyListPage` → watchlists + downloads management

### Responsive Layout

`ResponsiveLayout` class (in `lib/core/responsive.dart`) provides breakpoints:
- Phone: < 720px — uses bottom nav
- Tablet: 720-1100px
- Desktop: > 1100px — uses desktop nav links

All pages check `layout.isPhone` / `layout.isTablet` / `layout.isDesktop` for adaptive layouts.

### Theme & Styling

- Dark theme defined in `AppTheme` (`lib/core/theme.dart`)
- Font: SF Pro Display (loaded from `assets/fonts/`)
- Accent color: `#FF3B40` (Netflix red)
- Background: `#0B0F14`
- All interactive elements use `HoverButton` widget for focus/hover/TV remote support

### Video Source System

5 VOD providers defined in `ApiService.sources`. User can switch default source in Settings. `ApiService._activeBaseUrl` resolves to the current source. When source changes, caches are cleared and HomePage refreshes.

### Configuration

API keys in `lib/config/app_config.dart`:
- TMDB API key (required for metadata)
- SubDL API key (optional, for subtitles)
- OpenSubtitles API key (optional, disabled by default)

Firebase config is via `AuthService._apiKey` (hardcoded in `lib/services/auth_service.dart`).

### State Management

No external state management library. Uses:
- `StatefulWidget` with `setState` throughout
- `ChangeNotifier` for `WatchlistService` and `DownloadService` (with `addListener`/`removeListener`)
- Static singletons for `ApiService`, `WatchlistService`, `DownloadService`
- Static variables for `AuthService` (auth state) and `TmdbService` (language)
- `SharedPreferences` for local persistence (caching, watchlists, downloads)
- Firebase RTDB for cloud user data

### Rules
- Do not overthink, just do it
