# M3UKit

M3UKit is a Swift package for parsing M3U and M3U8 playlists in iOS, macOS, tvOS, watchOS, and server-side Swift apps.

It focuses on IPTV playlists while preserving enough HLS metadata for media clients that need more than a flat list of URLs.

## Features

- Parse extended M3U playlists from `String`, `Data`, or file `URL`
- Model playlists and media entries with `Codable`, `Hashable`, and `Sendable` types
- Preserve IPTV attributes such as `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, `audio-track`, and catch-up fields
- Preserve HLS metadata such as playlist type, target duration, media sequence, keys, byte ranges, maps, and discontinuities
- Classify entries as live channels, movies, series, radio, shows, or other media
- Detect common series episode patterns such as `S01E02`, `1x08`, and `Season 2 Episode 5`
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

## Requirements

- Swift 6.3 or newer
- Apple platforms supported by Swift Package Manager, or server-side Swift environments with Foundation

## License

M3UKit is released under the MIT License. See [LICENSE](LICENSE).
