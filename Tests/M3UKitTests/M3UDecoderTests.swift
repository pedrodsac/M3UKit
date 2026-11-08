import Foundation
import Testing
@testable import M3UKit

@Test func decodesIPTVPlaylistMetadataAndEntries() throws {
    let text = """
    #EXTM3U x-tvg-url="https://example.com/epg.xml" catchup="append" catchup-source="?utc={utc}&duration={duration}"
    #EXT-X-TARGETDURATION:10
    #EXT-X-MEDIA-SEQUENCE:42
    #EXTINF:-1 tvg-id="hbo.us" tvg-name="HBO HD" tvg-logo="https://example.com/hbo.png" group-title="Movies",HBO HD
    https://example.com/live/hbo/index.m3u8
    #EXTGRP:Series
    #EXTINF:0 tvg-type="series",The Show S02E05
    https://example.com/series/the-show/s02e05.mkv
    #EXT-X-ENDLIST
    """

    let playlist = try M3UDecoder().decode(text)

    #expect(playlist.isExtended)
    #expect(playlist.attributes["x-tvg-url"] == "https://example.com/epg.xml")
    #expect(playlist.targetDuration == 10)
    #expect(playlist.mediaSequence == 42)
    #expect(playlist.hasEndList)
    #expect(playlist.media.count == 2)

    let hbo = try #require(playlist.media.first)
    #expect(hbo.title == "HBO HD")
    #expect(hbo.duration == -1)
    #expect(hbo.tvgID == "hbo.us")
    #expect(hbo.groupTitle == "Movies")
    #expect(hbo.contentType == .movie)
    #expect(hbo.tvgLogo?.absoluteString == "https://example.com/hbo.png")

    let episode = playlist.media[1]
    #expect(episode.contentType == .series)
    #expect(episode.groupTitle == "Series")
    #expect(episode.series?.name == "The Show")
    #expect(episode.series?.season == 2)
    #expect(episode.series?.episode == 5)
}

@Test func decodesHLSMetadataForFollowingMedia() throws {
    let text = """
    #EXTM3U
    #EXT-X-KEY:METHOD=AES-128,URI="https://example.com/key",IV=0x1234
    #EXT-X-MAP:URI="init.mp4",BYTERANGE="720@0"
    #EXT-X-BYTERANGE:75232@720
    #EXT-X-DISCONTINUITY
    #EXTINF:9.5,Segment One
    segment1.ts
    #EXTINF:9.0,Segment Two
    segment2.ts
    """

    let playlist = try M3UDecoder().decode(text)

    #expect(playlist.media.count == 2)
    #expect(playlist.media[0].hls.key?.method == "AES-128")
    #expect(playlist.media[0].hls.key?.uri?.absoluteString == "https://example.com/key")
    #expect(playlist.media[0].hls.map?.uri?.relativeString == "init.mp4")
    #expect(playlist.media[0].hls.byteRange == ByteRange(length: 75232, offset: 720))
    #expect(playlist.media[0].hls.hasDiscontinuity)

    #expect(playlist.media[1].hls.key?.method == "AES-128")
    #expect(playlist.media[1].hls.byteRange == nil)
    #expect(!playlist.media[1].hls.hasDiscontinuity)
}

@Test func decodesVLCEDirectivesForFollowingMedia() throws {
    let text = """
    #EXTM3U
    #EXTINF:-1 group-title="TV" tvg-id="SIC.pt" tvg-logo="https://example.com/sic.png",SIC
    #EXTVLCOPT:http-user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0"
    #EXTVLCOPT:http-origin=https://sic.pt
    #EXTVLCOPT:http-referrer=https://sic.pt/
    https://sic.live.impresa.pt/sic1080p.m3u8
    #EXTINF:-1 tvg-id="rtp1.pt",RTP 1
    https://example.com/rtp1.m3u8
    """

    let playlist = try M3UDecoder().decode(text)

    let sic = playlist.media[0]
    #expect(sic.vlcOptions["http-user-agent"] == "Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0")
    #expect(sic.vlcOptions["http-origin"] == "https://sic.pt")
    #expect(sic.vlcOptions["http-referrer"] == "https://sic.pt/")
    #expect(sic.httpUserAgent == "Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0")
    #expect(sic.httpReferrer == "https://sic.pt/")
    #expect(sic.httpOrigin == "https://sic.pt")
    #expect(sic.httpHeaders == [
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0",
        "Referer": "https://sic.pt/",
        "Origin": "https://sic.pt",
    ])

    // `#EXTVLCOPT` describes the entry that follows, so the next entry gets none of it.
    #expect(playlist.media[1].vlcOptions.isEmpty)
    #expect(playlist.media[1].httpHeaders.isEmpty)

    // The directives belong to the media entry, not to the playlist-level tag list.
    #expect(playlist.tags.isEmpty)
}

@Test func decodesVLCEDirectivesWithoutQuotesOrValues() throws {
    let text = """
    #EXTM3U
    #EXTINF:-1,Channel
    #EXTVLCOPT:network-caching=1000
    #EXTVLCOPT:no-video-title-show
    #EXTVLCOPT:http-user-agent='Firefox'
    https://example.com/live/channel.m3u8
    """

    let playlist = try M3UDecoder().decode(text)
    let channel = try #require(playlist.media.first)

    #expect(channel.vlcOptions["network-caching"] == "1000")
    #expect(channel.vlcOptions["no-video-title-show"] == "")
    // Only matching double quotes are stripped; single quotes are left as written.
    #expect(channel.vlcOptions["http-user-agent"] == "'Firefox'")
}

@Test func buildsCatchUpURLs() throws {
    let text = """
    #EXTM3U catchup="append" catchup-source="?utc={utc}&duration={duration}"
    #EXTINF:-1,Channel
    https://example.com/live/channel.m3u8
    """

    let playlist = try M3UDecoder().decode(text)
    let media = try #require(playlist.media.first)
    let url = media.catchUpURL(
        startDate: Date(timeIntervalSince1970: 1_700_000_000),
        duration: 3_600,
        playlistAttributes: playlist.attributes
    )

    #expect(url?.absoluteString == "https://example.com/live/channel.m3u8?utc=1700000000&duration=3600")
}

@Test func modelsRoundTripThroughCodable() throws {
    let original = Playlist(
        media: [
            Media(
                title: "Movie",
                url: try #require(URL(string: "https://example.com/movie.mp4")),
                duration: 120,
                attributes: ["tvg-type": "movie"],
                contentType: .movie
            )
        ],
        attributes: ["source": "test"],
        playlistType: .vod,
        hasEndList: true,
        isExtended: true
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Playlist.self, from: data)

    #expect(decoded == original)
    #expect(Set(decoded.media).count == 1)
}
