# Changelog

## 2.0.0 - 2026-11-10

Breaking: entries are classified differently, so the same playlist can come out with different `contentType`s.

- Classification now trusts the link over the group. A panel's `/live/`, `/movie/` and `/series/` paths, its short live form (`/user/pass/123`) and XUI's `/play/{token}` links decide the kind first, then the container extension, and only then the title and the group. Group names match whole words only, so "Sky Cinema", "Filmbox", "Vodafone" and "Comedy Shows" no longer turn live channels into movies, series or radio, and `music` and `kids` no longer decide anything
- `MediaClassifier.classify(title:url:attributes:group:isVODPlaylist:)` is public
- Episode titles parse `S02 E03`, `S01.E01`, `1x02` and `Season 2 Ep 5` as well as `S02E03`, and the show name is the text before the marker. `Show - S01E01 - Pilot` is the show `Show`, not `Show Pilot`
- `SeriesInfo` gains `episodeTitle`, `year` and `airDate`, and `SeriesInfo(title:)` is public
- Added `XtreamStreamURL`, `Media.xtreamStreamID` and `Playlist.isXUI`
- `#EXT-X-SESSION-DATA` tags keep their attributes
- The episode patterns are compiled once instead of for every entry: decoding 300,000 entries went from 14.2 s to 5.1 s

- Parse `#EXTVLCOPT:` directives and attach them to the media entry that follows, exposed as `Media.vlcOptions`
- Added `Media.httpUserAgent`, `Media.httpReferrer`, `Media.httpOrigin` and `Media.httpHeaders` accessors

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
