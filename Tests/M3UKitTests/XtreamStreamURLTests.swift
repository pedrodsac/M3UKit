import Foundation
import Testing
@testable import M3UKit

private struct StreamLink: CustomTestStringConvertible, Sendable {
    var url: String
    var kind: XtreamStreamURL.Kind
    var streamID: Int
    var username: String
    var password: String
    var containerExtension: String?

    var testDescription: String { url }
}

private let links: [StreamLink] = [
    StreamLink(url: "http://host:8080/live/johndoe/s3cret/10234.m3u8", kind: .live, streamID: 10234, username: "johndoe", password: "s3cret", containerExtension: "m3u8"),
    StreamLink(url: "http://host:8080/live/johndoe/s3cret/10234.ts", kind: .live, streamID: 10234, username: "johndoe", password: "s3cret", containerExtension: "ts"),
    StreamLink(url: "http://host:8080/johndoe/s3cret/10234", kind: .live, streamID: 10234, username: "johndoe", password: "s3cret"),
    StreamLink(url: "http://host:8080/johndoe/s3cret/10234.ts", kind: .live, streamID: 10234, username: "johndoe", password: "s3cret", containerExtension: "ts"),
    StreamLink(url: "http://host:8080/movie/johndoe/s3cret/55120.MKV", kind: .movie, streamID: 55120, username: "johndoe", password: "s3cret", containerExtension: "mkv"),
    StreamLink(url: "http://host:8080/series/johndoe/s3cret/90311.mp4", kind: .series, streamID: 90311, username: "johndoe", password: "s3cret", containerExtension: "mp4"),
    StreamLink(url: "http://host:8080/timeshift/johndoe/s3cret/120/2026-11-10:20-00/10234.ts", kind: .timeshift, streamID: 10234, username: "johndoe", password: "s3cret", containerExtension: "ts"),
    // A panel mounted below the host's root.
    StreamLink(url: "https://host/panel/live/johndoe/s3cret/10234.m3u8", kind: .live, streamID: 10234, username: "johndoe", password: "s3cret", containerExtension: "m3u8"),
    // The path is split before it's decoded, so a slash in a password stays inside it.
    StreamLink(url: "http://host/live/john%40doe/pa%2Fss%2B/7.ts", kind: .live, streamID: 7, username: "john@doe", password: "pa/ss+", containerExtension: "ts"),
]

@Test(arguments: links)
private func parsesPanelLinks(_ link: StreamLink) throws {
    let url = try #require(URL(string: link.url))
    let stream = try #require(XtreamStreamURL(url: url))
    #expect(stream.kind == link.kind)
    #expect(stream.streamID == link.streamID)
    #expect(stream.username == link.username)
    #expect(stream.password == link.password)
    #expect(stream.containerExtension == link.containerExtension)
}

@Test(arguments: [
    "https://example.com/live/hbo/index.m3u8",
    "https://example.com/live/channel.m3u8",
    "http://host/play/abc123/ts",
    "http://host/play/abc123#.mp4",
    "http://host/a/b/c.mp4",
    "http://host/movie/u/p/abc.mp4",
    "http://host/live/u/123",
    "http://host",
    "http://host:8080/u/p/12.mkv",
])
private func ignoresLinksThatAreNotAPanelsStream(_ link: String) throws {
    let url = try #require(URL(string: link))
    #expect(XtreamStreamURL(url: url) == nil)
}

@Test func tokenisedLinksTakeTheirIDFromTheEntry() throws {
    let media = Media(
        title: "Demo",
        url: try #require(URL(string: "http://host/play/abc123/ts")),
        attributes: ["xui-id": "5520"]
    )
    #expect(media.xtreamStreamID == 5520)

    let plain = Media(title: "Other", url: try #require(URL(string: "http://cdn.example/x/stream.m3u8")))
    #expect(plain.xtreamStreamID == nil)
}
