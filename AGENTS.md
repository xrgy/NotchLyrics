# Repository Guidelines

## Project Structure & Module Organization

This repository is a Swift Package Manager macOS app.

- `Package.swift`: package manifest and platform settings.
- `Sources/NotchLyrics/`: all application source files.
  - `NotchLyricsApp.swift`: app entry point.
  - `AppModel.swift`: app state and polling logic.
  - `Spotify*.swift`: Spotify auth and playback integration.
  - `LRCLibClient.swift`: lyrics lookup.
  - `NotchOverlayView.swift`, `MenuBarView.swift`, `NotchPanelController.swift`: UI and floating panel behavior.
- `packaging/Info.plist`: app bundle metadata.
- `dist/NotchLyrics.app/`: built app bundle for local use.
- `.build/`: SwiftPM build artifacts. Do not edit manually.

## Build, Test, and Development Commands

- `swift build`: debug build for local development.
- `swift build -c release`: create the release binary in `.build/release/NotchLyrics`.
- `./.build/release/NotchLyrics`: run the compiled binary directly.
- `open dist/NotchLyrics.app`: launch the packaged app bundle.

If SwiftPM cache or sandbox issues appear, use the repository-local module cache already used in development:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache swift build -c release
```

## Coding Style & Naming Conventions

- Use Swift 6 style with 4-space indentation.
- Prefer small, focused types; keep UI, networking, and state management separated by file.
- Use `UpperCamelCase` for types and `lowerCamelCase` for properties and methods.
- Keep filenames aligned with primary types, for example `SpotifyClient.swift` and `AppModel.swift`.
- Avoid unnecessary dependencies; prefer system frameworks (`SwiftUI`, `AppKit`, `Foundation`).

## Testing Guidelines

There is currently no `Tests/` target. New logic-heavy work should add targeted SwiftPM tests in `Tests/NotchLyricsTests/`.

- Name tests by behavior, for example `testCurrentTrackReturnsNilFor204Response()`.
- Prioritize parsing, auth flow helpers, and API response handling.

## Commit & Pull Request Guidelines

Git history is not available in this workspace, so use clear imperative commit messages:

- `Add Spotify error decoding`
- `Adjust floating notch panel layout`

Pull requests should include:

- a short summary of user-visible changes
- any config changes such as `SPOTIFY_CLIENT_ID` or redirect URI updates
- screenshots or screen recordings for UI changes
- brief verification notes with commands run

## Security & Configuration Tips

- Never commit Spotify credentials or user tokens.
- Store local config in `~/Library/Application Support/NotchLyrics/config.json`.
- Treat `dist/NotchLyrics.app` as a generated artifact; rebuild it after source changes.
