# Changelog

## 2.2.0 - 2026-11-12

Entries can be classified differently: a `media="true"` entry is no longer live, and a dated on-demand title is an episode.

- `media="true"` (Kodi's IPTV Simple convention for catch-up programmes and recordings) marks an entry as on demand, after `tvg-type` and before the link. The link can still say movie or episode; otherwise an episode marker, a dated title or a series word makes an episode, a video file, a year in brackets or a movie word makes a movie, and anything else is `other`
- An on-demand title that names its episode only by its air date (`Show - 5/11/2026`, `Show 2026-11-05`, `Show 05 05 25`) is an episode of `Show`, with `airDate` set and no season or episode. A link that says nothing still needs more than a date, since live events put dates in their titles
- `MediaClassifier.classification(title:url:attributes:group:isVODPlaylist:)` returns the kind and the `SeriesInfo` together, as `MediaClassification`. `M3UDecoder` uses it, so `Media.series` names dated episodes

## 2.1.0 - 2026-11-10

- Added the `XtreamKit` library for Xtream Codes and XUI panels
  - `XtreamAccount` reads an account from a panel link or from a typed address, and builds the panel's URLs: `player_api.php`, `get.php`, `xmltv.php`, live, movie and episode streams, and catch-up in both its path and query forms
  - `XtreamClient` is an actor over `player_api.php`: the account, categories, live streams, movies, series, movie and series details, and the guide. At most four requests run at once, server errors are retried, and large lists are downloaded to a file and decoded from a memory-mapped view of it. A list the panel can't deliver whole is fetched category by category
  - The models read what panels really send: numbers as strings, `null`, `""`, `[]` for a missing object, `backdrop_path` as an array or a string, `episodes` keyed by season or as an array of arrays, a list as an object of items, base64 guide text. One malformed item is skipped and counted instead of failing the list
  - `XtreamClient.vodInfoData(id:)` and `seriesInfoData(id:)` give a detail answer as the panel sent it, after the usual checks, for an app that stores the answer and decodes it again later with `XtreamVODInfo` or `XtreamSeriesInfo`
  - `XtreamError` says why a request gave no data: rejected, expired, disabled, banned, a web page instead of data, an unexpected status
- Raised the minimum platforms to macOS 13, iOS 16, tvOS 16 and watchOS 9, which the client's async `URLSession` calls need

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
