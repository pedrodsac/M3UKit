# M3UKit

M3UKit is a Swift package for parsing M3U and M3U8 playlists in iOS, macOS, tvOS, watchOS, and server-side Swift apps.

It focuses on IPTV playlists while preserving enough HLS metadata for media clients that need more than a flat list of URLs.

## Features

- Parse extended M3U playlists from `String`, `Data`, or file `URL`
- Model playlists and media entries with `Codable`, `Hashable`, and `Sendable` types
- Preserve IPTV attributes such as `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, `audio-track`, and catch-up fields
- Preserve per-entry `#EXTVLCOPT:` options such as a pinned user agent, referrer, and origin
- Preserve HLS metadata such as playlist type, target duration, media sequence, keys, byte ranges, maps, and discontinuities
- Classify entries as live channels, movies, series, radio, shows, or other media, trusting the stream link over the group name
- Read episode titles such as `S01E02`, `S01 E02`, `1x08`, and `Season 2 Episode 5` into show, season, episode, episode name, year, and air date
- Recognise Xtream Codes and XUI stream links and read their IDs
- Build catch-up URLs from provider templates
- Tested with Swift Testing

## Installation

Add M3UKit as a Swift Package Manager dependency:

```swift
dependencies: [
    .package(url: "https://github.com/pedrodsac/M3UKit.git", from: "1.0.0")
]
```

Then add `M3UKit` to your target dependencies.

## Usage

```swift
import M3UKit

let playlistText = """
#EXTM3U
#EXTINF:-1 tvg-id="hbo.us" tvg-name="HBO HD" group-title="Movies",HBO HD
https://example.com/live/hbo/index.m3u8
"""

let playlist = try M3UDecoder().decode(playlistText)

for media in playlist.media {
    print(media.title)
    print(media.url)
    print(media.contentType)
    print(media.tvgID ?? "No TVG ID")
}
```

## Models

The package exposes two primary models:

- `Playlist`: the parsed playlist, top-level attributes, HLS playlist metadata, and media entries.
- `Media`: one playable entry with title, URL, duration, IPTV attributes, inferred content type, series information, and HLS metadata for that item.

Both types conform to `Codable`, `Hashable`, and `Sendable`.

## Classification

`MediaClassifier` decides whether an entry is live, a movie, an episode or radio. The link is the strongest
evidence, because an IPTV panel writes it, while group names are whatever the provider typed:

1. An explicit `tvg-type`.
2. `media="true"`, which marks a catch-up programme or a recording rather than a channel. It is never live: the
   link can still say movie or episode; otherwise an episode marker, a dated title or a series word makes an
   episode, a video file, a year in brackets or a movie word in the group makes a movie, and anything else is
   `other`.
3. The link's shape: a panel's `/live/`, `/movie/` and `/series/` paths, the short live form `/user/pass/123`, and
   XUI's `/play/{token}` links.
4. The container extension: a video file is on demand, an audio file is radio.
5. For on-demand entries, an episode marker in the title, a title that ends in an air date (`Show - 5/11/2026`), or
   a series word in the group makes an episode; otherwise a movie.
6. For a link that says nothing, an episode marker, then words in the group, then an `audio-track` attribute.
   Otherwise live. A date alone doesn't make an episode here, because live events put dates in their titles too.

Group words match whole words only, so "Vodafone" is not "vod" and "Filmbox" is not "film".

```swift
let kind = MediaClassifier.classify(title: "Sky Cinema", url: url, attributes: [:], group: "UK | Sky Cinema")

// The kind and the episode together: a dated title names an episode only once the entry is known to be on demand.
let result = MediaClassifier.classification(title: "Eixo do Mal - 5/11/2026", url: url, attributes: ["media": "true"], group: nil)
result.contentType      // .series
result.series?.name     // "Eixo do Mal"
result.series?.airDate  // "5/11/2026"

let info = SeriesInfo(title: "Severance S02 E03 - Hello, Ms. Cobel")
info?.name          // "Severance"
info?.season        // 2
info?.episode       // 3
info?.episodeTitle  // "Hello, Ms. Cobel"

let stream = XtreamStreamURL(url: url)   // kind, streamID, username, password, containerExtension
media.xtreamStreamID                      // from the link, or an XUI entry's `xui-id`
playlist.isXUI
```

## Catch-Up URLs

M3UKit preserves catch-up attributes and can render template-based catch-up URLs:

```swift
let url = media.catchUpURL(
    startDate: Date(timeIntervalSince1970: 1_700_000_000),
    duration: 3_600,
    playlistAttributes: playlist.attributes
)
```

Supported modes are `default`, `append`, `shift`, `flussonic`, and `xtream`.

## VLC Options

Providers often pin request headers on an entry with `#EXTVLCOPT:` lines:

```m3u
#EXTINF:-1 tvg-id="sic.pt",SIC
#EXTVLCOPT:http-user-agent="Mozilla/5.0 …"
#EXTVLCOPT:http-origin=https://sic.pt
#EXTVLCOPT:http-referrer=https://sic.pt/
https://sic.live.impresa.pt/sic1080p.m3u8
```

M3UKit attaches those options to the entry they precede and exposes them both raw and as
ready-to-use HTTP headers:

```swift
let media = playlist.media[0]

media.vlcOptions            // ["http-user-agent": "Mozilla/5.0 …", "http-origin": "https://sic.pt", …]
media.httpUserAgent         // "Mozilla/5.0 …"
media.httpHeaders           // ["User-Agent": "Mozilla/5.0 …", "Origin": "https://sic.pt", "Referer": "https://sic.pt/"]
```

## XtreamKit

`XtreamKit` is a second library in the package for Xtream Codes and XUI panels. It depends on M3UKit and is
imported separately.

```swift
import XtreamKit

let account = XtreamAccount(link: "http://panel.example:8080/get.php?username=…&password=…")!
let client = XtreamClient(account: account)

let info = try await client.accountInfo()
try info.requireUsable()                       // throws .accountExpired, .accountBanned, .accountRejected …

let categories = try await client.categories(.live)
let channels = try await client.liveStreams()   // channels.items, channels.droppedCount
let movie = try await client.vodInfo(id: 55120)
let show = try await client.seriesInfo(id: 901)

account.liveURL(streamID: 10234, containerExtension: info.preferredLiveExtension)
account.xmltvURL
```

Panels send JSON with no reliable types, so every model reads numbers as strings, `null`, `""` and `[]` for a
missing object, and one item that can't be read is skipped and counted rather than failing the list.

## Requirements

- Swift 6.3 or newer
- macOS 13, iOS 16, tvOS 16 or watchOS 9, or server-side Swift environments with Foundation

## License

M3UKit is released under the MIT License. See [LICENSE](LICENSE).
