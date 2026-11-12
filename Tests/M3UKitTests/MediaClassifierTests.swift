import Foundation
import Testing
@testable import M3UKit

private struct Entry: CustomTestStringConvertible, Sendable {
    var title: String
    var url: String
    var group: String?
    var attributes: [String: String] = [:]
    var expected: MediaContentType

    var testDescription: String { "\(title) [\(group ?? "-")] → \(expected)" }
}

// Entries real Xtream panels produce, which the group-first classifier got wrong.
private let misfiledByGroup: [Entry] = [
    Entry(title: "Sky Cinema Premiere", url: "http://host:8080/live/u/p/101.ts", group: "UK | Sky Cinema", expected: .live),
    Entry(title: "Filmbox Arthouse", url: "http://host:8080/u/p/102", group: "PL | Filmbox", expected: .live),
    Entry(title: "Comedy Central", url: "http://host:8080/u/p/103", group: "US | Comedy Shows", expected: .live),
    Entry(title: "MTV Hits", url: "http://host:8080/u/p/104", group: "Music Channels", expected: .live),
    Entry(title: "Vodafone Sport", url: "http://host:8080/u/p/105", group: "PT | Vodafone", expected: .live),
    Entry(title: "24/7 Friends", url: "http://host:8080/u/p/106", group: "24/7 Series", expected: .live),
    Entry(title: "The Batman (2022)", url: "http://host:8080/movie/u/p/5001.mkv", group: "NEWS & DOCS | Live Action", expected: .movie),
    Entry(title: "Sports documentary", url: "http://host:8080/movie/u/p/5002.mp4", group: "Sports", expected: .movie),
    Entry(title: "Bluey S01E01", url: "http://host:8080/series/u/p/9001.mp4", group: "Kids", expected: .series),
]

// What each panel writes for each kind of entry.
private let panelShapes: [Entry] = [
    Entry(title: "UK: BBC One HD", url: "http://host:8080/johndoe/s3cret/10234", group: "UK | Entertainment", expected: .live),
    Entry(title: "UK: BBC One HD", url: "http://host:8080/live/johndoe/s3cret/10234.m3u8", expected: .live),
    Entry(title: "UK: BBC One HD", url: "http://host:8080/live/johndoe/s3cret/10234.ts", expected: .live),
    Entry(title: "Dune: Part Two (2024)", url: "http://host:8080/movie/johndoe/s3cret/55120.mkv", group: "VOD | Sci-Fi", expected: .movie),
    Entry(title: "Severance S02 E03", url: "http://host:8080/series/johndoe/s3cret/90311.mp4", group: "SERIES | Apple TV+", expected: .series),
    Entry(title: "Replay", url: "http://host:8080/timeshift/u/p/120/2026-11-10:20-00/10234.ts", expected: .live),
    Entry(title: "Radio Nova", url: "http://host:8080/radio/u/p/77.mp3", expected: .radio),
]

private let xuiShapes: [Entry] = [
    Entry(title: "Demo Live", url: "http://203.0.113.10:80/play/abc123def456/ts", group: "News", attributes: ["xui-id": "5520"], expected: .live),
    Entry(title: "Demo Live", url: "http://203.0.113.10:80/play/abc123def456/m3u8", group: "Movies", attributes: ["xui-id": "5520"], expected: .live),
    Entry(title: "Demo Movie (2021)", url: "http://203.0.113.10:80/play/abc123def456#.mp4", group: "Drama", attributes: ["xui-id": "5522"], expected: .movie),
    Entry(title: "Demo Show S01E01", url: "http://203.0.113.10:80/play/abc123def456#.mp4", group: "Comedy", attributes: ["xui-id": "5523"], expected: .series),
]

private let ambiguousLinks: [Entry] = [
    Entry(title: "Inception (2010)", url: "http://cdn.example/x/index.m3u8", group: "Movies", expected: .movie),
    Entry(title: "CNN", url: "http://cdn.example/x/stream.m3u8", group: "News", expected: .live),
    Entry(title: "Sky Cinema Premiere", url: "http://cdn.example/x/stream.m3u8", group: "Cinema", expected: .live),
    Entry(title: "Show S01E01", url: "http://cdn.example/x/stream.m3u8", group: "Entertainment", expected: .series),
    Entry(title: "Smooth Jazz", url: "http://cdn.example/x/stream", group: "Radio", expected: .radio),
    Entry(title: "Some Station", url: "http://cdn.example/x/stream", attributes: ["audio-track": "en"], expected: .radio),
    Entry(title: "Anything", url: "http://host/vod/film.mp4", group: "Kids", expected: .movie),
    Entry(title: "Show 2x05", url: "http://host/vod/show.mp4", expected: .series),
]

private let containers: [Entry] = [
    Entry(title: "Film", url: "http://cdn.example/a/film.mp4", group: "Kids", expected: .movie),
    Entry(title: "Show 1x02", url: "http://cdn.example/a/show.mkv", expected: .series),
    Entry(title: "Documentary", url: "http://cdn.example/a/doc.avi", group: "Talk Shows", expected: .series),
    Entry(title: "Song", url: "http://cdn.example/a/song.mp3", expected: .radio),
]

private let explicit: [Entry] = [
    Entry(title: "Anything", url: "http://host:8080/movie/u/p/1.mkv", attributes: ["tvg-type": "live"], expected: .live),
    Entry(title: "Anything", url: "http://host:8080/u/p/2", attributes: ["tvg-type": "series"], expected: .series),
]

// `media="true"` entries, as a broadcaster's catch-up list writes them: plain HLS links that say nothing themselves.
private let mediaEntries: [Entry] = [
    Entry(title: "Eixo do Mal - 5/11/2026", url: "https://videos.example/hls/2026/11/06/548a0920/video.m3u8", group: "Eixo do Mal", attributes: ["media": "true"], expected: .series),
    Entry(title: "IEGCQT S14E10 8-11-2026", url: "https://cdn.example/manifest.mpd", group: "IEGCQT", attributes: ["media": "true"], expected: .series),
    Entry(title: "Highlights", url: "https://videos.example/hls/clip/video.m3u8", group: "Sport", attributes: ["media": "true"], expected: .other),
    Entry(title: "Dune (2021)", url: "https://videos.example/hls/dune/video.m3u8", group: "Drama", attributes: ["media": "true"], expected: .movie),
    Entry(title: "Trailer", url: "https://videos.example/trailer.mp4", group: "Extras", attributes: ["media": "TRUE"], expected: .movie),
    Entry(title: "Anything", url: "https://videos.example/hls/x/video.m3u8", group: "Filmes", attributes: ["media": "true"], expected: .movie),
    Entry(title: "Recording", url: "http://host:8080/live/u/p/101.ts", group: "News", attributes: ["media": "true"], expected: .other),
    Entry(title: "Recording", url: "http://host:8080/series/u/p/9001.mp4", group: "News", attributes: ["media": "true"], expected: .series),
    Entry(title: "Podcast", url: "https://videos.example/episode.mp3", attributes: ["media": "true"], expected: .other),
    Entry(title: "RTP 1", url: "https://live.example/rtp1/playlist.m3u8", group: "TV", attributes: ["media": "false"], expected: .live),
]

// A title that ends in a date names an episode only when something else already says the entry is on demand.
private let datedTitles: [Entry] = [
    Entry(title: "Telejornal - 2026-11-05", url: "http://host/vod/telejornal.mp4", group: "News", expected: .series),
    Entry(title: "Telejornal 05.11.2026", url: "https://cdn.example/a/telejornal.mkv", expected: .series),
    Entry(title: "UFC 300 - 13/04/2024", url: "https://cdn.example/x/stream.m3u8", group: "PPV", expected: .live),
    Entry(title: "UFC 300 - 13/04/2024", url: "http://host:8080/live/u/p/300.ts", group: "PPV", expected: .live),
    Entry(title: "Concert 1/2/3456", url: "http://host/vod/concert.mp4", expected: .movie),
]

private let allEntries: [Entry] = [
    misfiledByGroup, panelShapes, xuiShapes, ambiguousLinks, containers, explicit, mediaEntries, datedTitles,
].flatMap { $0 }

@Test(arguments: allEntries)
private func classifiesEntry(_ entry: Entry) throws {
    let url = try #require(URL(string: entry.url))
    let kind = MediaClassifier.classify(title: entry.title, url: url, attributes: entry.attributes, group: entry.group)
    #expect(kind == entry.expected)
}

@Test func classificationNamesADatedEpisodesShow() throws {
    let url = try #require(URL(string: "https://videos.example/hls/2026/11/06/548a0920/video.m3u8"))
    let result = MediaClassifier.classification(
        title: "Eixo do Mal - 5/11/2026",
        url: url,
        attributes: ["media": "true"],
        group: "Eixo do Mal"
    )

    #expect(result.contentType == .series)
    #expect(result.series == SeriesInfo(name: "Eixo do Mal", airDate: "5/11/2026"))
}

@Test func classificationLeavesALiveEventsDateAlone() throws {
    let url = try #require(URL(string: "https://cdn.example/x/stream.m3u8"))
    let result = MediaClassifier.classification(title: "UFC 300 - 13/04/2024", url: url, attributes: [:], group: "PPV")

    #expect(result == MediaClassification(contentType: .live))
}

@Test func classificationKeepsAMarkerOnAnyKind() throws {
    let url = try #require(URL(string: "http://host:8080/live/u/p/101.ts"))
    let result = MediaClassifier.classification(title: "Show S01E02", url: url, attributes: [:], group: nil)

    #expect(result.contentType == .live)
    #expect(result.series == SeriesInfo(name: "Show", season: 1, episode: 2))
}

@Test func anHLSVODPlaylistIsMovies() throws {
    let url = try #require(URL(string: "http://cdn.example/x/segment1.ts"))
    #expect(MediaClassifier.classify(title: "Segment", url: url, attributes: [:], group: nil, isVODPlaylist: true) == .movie)
    #expect(MediaClassifier.classify(title: "Segment", url: url, attributes: [:], group: nil) == .live)
}

@Test func decoderClassifiesAClassicXtreamExport() throws {
    let text = """
    #EXTM3U
    #EXTINF:-1 tvg-id="bbcone.uk" tvg-name="UK: BBC One HD" tvg-logo="http://logos.example/bbc1.png" group-title="UK | Sky Cinema",UK: BBC One HD
    http://example.com:8080/johndoe/s3cret/10234
    #EXTINF:-1 tvg-id="" tvg-name="Dune: Part Two (2024)" group-title="VOD | Sci-Fi",Dune: Part Two (2024)
    http://example.com:8080/movie/johndoe/s3cret/55120.mkv
    #EXTINF:-1 tvg-id="" tvg-name="Severance S02 E03" group-title="SERIES | Apple TV+",Severance S02 E03
    http://example.com:8080/series/johndoe/s3cret/90311.mp4
    """

    let playlist = try M3UDecoder().decode(text)

    #expect(playlist.media.map(\.contentType) == [.live, .movie, .series])
    #expect(playlist.media.map(\.xtreamStreamID) == [10234, 55120, 90311])
    #expect(playlist.media[2].series?.name == "Severance")
    #expect(playlist.media[2].series?.season == 2)
    #expect(playlist.media[2].series?.episode == 3)
    #expect(playlist.isXUI == false)
}

@Test func decoderClassifiesAnXUIExport() throws {
    let text = """
    #EXTM3U
    #EXT-X-SESSION-DATA:DATA-ID="com.xui.dev"
    #EXTINF:-1 xui-id="5520" tvg-id="demo.channel" tvg-name="Demo Live" tvg-logo="" group-title="News",Demo Live
    http://203.0.113.10:80/play/abc123def456/ts
    #EXTINF:-1 xui-id="5522" tvg-name="Demo Movie (2021)" tvg-logo="" group-title="Drama",Demo Movie (2021)
    http://203.0.113.10:80/play/abc123def456#.mp4
    #EXTINF:-1 xui-id="5523" tvg-name="Demo Show S01E01" tvg-logo="" group-title="Comedy",Demo Show S01E01
    http://203.0.113.10:80/play/abc123def456#.mp4
    """

    let playlist = try M3UDecoder().decode(text)

    #expect(playlist.isXUI)
    #expect(playlist.media.map(\.contentType) == [.live, .movie, .series])
    #expect(playlist.media.map(\.xtreamStreamID) == [5520, 5522, 5523])
}

@Test func decoderClassifiesABroadcastersCatchUpList() throws {
    let text = """
    #EXTM3U
    #EXTINF:-1 tvg-id="RTP1.pt" group-title="TV",RTP 1
    https://live.example/rtp1/playlist.m3u8
    #EXTINF:-1 radio="true" group-title="Rádios",Antena 1
    https://live.example/antena1/playlist.m3u8
    #EXTINF:-1 group-title="Beachcam",Viana do Castelo | Cabedelo
    https://video.example/beachcam/cabedelo/playlist.m3u8
    #EXTINF:-1 media="true" group-title="Eixo do Mal",Eixo do Mal - 5/11/2026
    https://videos.example/hls/2026/11/06/548a0920/video.m3u8
    #EXTINF:-1 media="true" group-title="O Planeta Vivo",O Planeta Vivo - S01E02
    https://vod.example/hls/p13613/index-v1-a1.m3u8
    """

    let playlist = try M3UDecoder().decode(text)

    #expect(playlist.media.map(\.contentType) == [.live, .radio, .live, .series, .series])
    #expect(playlist.media[3].series == SeriesInfo(name: "Eixo do Mal", airDate: "5/11/2026"))
    #expect(playlist.media[4].series == SeriesInfo(name: "O Planeta Vivo", season: 1, episode: 2))
}
