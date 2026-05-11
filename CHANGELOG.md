# Changelog

## 1.0.0 - 2026-05-11

Initial stable release.

- Added `Playlist` and `Media` models with `Codable`, `Hashable`, and `Sendable` conformance
- Added `M3UDecoder` for parsing playlists from strings, data, and files
- Added IPTV attribute parsing and typed convenience accessors
- Added HLS playlist and per-media metadata parsing
- Added media classification for live, movie, series, radio, show, and other content
- Added series episode detection
- Added catch-up URL generation
- Added Swift Testing coverage
