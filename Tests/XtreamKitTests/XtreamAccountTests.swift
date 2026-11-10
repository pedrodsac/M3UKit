import Foundation
import M3UKit
import Testing
@testable import XtreamKit

private let account = XtreamAccount(
    baseURL: URL(string: "http://panel.example:8080")!,
    username: "johndoe",
    password: "s3cret"
)

@Test(arguments: [
    "http://panel.example:8080/get.php?username=johndoe&password=s3cret&type=m3u_plus&output=ts",
    "http://panel.example:8080/player_api.php?username=johndoe&password=s3cret",
    "http://panel.example:8080/panel_api.php?password=s3cret&username=johndoe",
    "http://panel.example:8080/xmltv.php?username=johndoe&password=s3cret",
    "HTTP://panel.example:8080/GET.PHP?USERNAME=johndoe&PASSWORD=s3cret",
])
private func readsAnAccountOutOfAPanelLink(_ link: String) throws {
    let parsed = try #require(XtreamAccount(link: link))
    #expect(parsed.baseURL.absoluteString.lowercased() == "http://panel.example:8080")
    #expect(parsed.username == "johndoe")
    #expect(parsed.password == "s3cret")
}

@Test func keepsTheFolderAPanelIsMountedIn() throws {
    let parsed = try #require(XtreamAccount(link: "https://host.example/panel/c/get.php?username=a&password=b"))
    #expect(parsed.baseURL.absoluteString == "https://host.example/panel/c")
    #expect(parsed.liveURL(streamID: 1).absoluteString == "https://host.example/panel/c/live/a/b/1.m3u8")
}

@Test(arguments: [
    "http://panel.example/get.php?username=johndoe",
    "http://panel.example/get.php?password=s3cret",
    "http://panel.example/get.php?username=&password=s3cret",
    "http://panel.example/playlist.m3u?username=a&password=b",
    "ftp://panel.example/get.php?username=a&password=b",
    "http://panel.example/",
    "not a url",
])
private func rejectsALinkThatIsNotAPanelLink(_ link: String) {
    #expect(XtreamAccount(link: link) == nil)
}

@Test func readsCredentialsTheWayThePanelDoes() throws {
    // `+` in a query is a space, `%2B` is a plus and `%26` an ampersand.
    let parsed = try #require(XtreamAccount(link: "http://p.example/get.php?username=john%40doe&password=pa+ss%2Bword%26x"))
    #expect(parsed.username == "john@doe")
    #expect(parsed.password == "pa ss+word&x")

    #expect(parsed.liveURL(streamID: 7).absoluteString == "http://p.example/live/john%40doe/pa%20ss%2Bword%26x/7.m3u8")
    #expect(parsed.playerAPIURL().absoluteString == "http://p.example/player_api.php?username=john%40doe&password=pa%20ss%2Bword%26x")
}

@Test(arguments: [
    ("panel.example:8080", "http://panel.example:8080"),
    ("http://panel.example:8080/", "http://panel.example:8080"),
    ("  https://panel.example  ", "https://panel.example"),
    ("http://panel.example:8080/get.php?username=x&password=y", "http://panel.example:8080"),
    ("http://panel.example/player_api.php", "http://panel.example"),
    ("http://panel.example/c/", "http://panel.example/c"),
] as [(String, String)])
private func buildsAnAccountFromWhatAPersonTypes(_ server: String, _ expected: String) throws {
    let parsed = try #require(XtreamAccount(server: server, username: "u", password: "p"))
    #expect(parsed.baseURL.absoluteString == expected)
}

@Test func rejectsATypedAccountWithoutAServerOrCredentials() {
    #expect(XtreamAccount(server: "", username: "u", password: "p") == nil)
    #expect(XtreamAccount(server: "panel.example", username: "", password: "p") == nil)
    #expect(XtreamAccount(server: "panel.example", username: "u", password: "") == nil)
    #expect(XtreamAccount(server: "ftp://panel.example", username: "u", password: "p") == nil)
}

@Test func buildsPanelFileURLs() {
    #expect(account.playerAPIURL().absoluteString == "http://panel.example:8080/player_api.php?username=johndoe&password=s3cret")
    #expect(
        account.playerAPIURL(action: "get_vod_info", parameters: [("vod_id", "12")]).absoluteString
            == "http://panel.example:8080/player_api.php?username=johndoe&password=s3cret&action=get_vod_info&vod_id=12"
    )
    #expect(
        account.playlistURL().absoluteString
            == "http://panel.example:8080/get.php?username=johndoe&password=s3cret&type=m3u_plus&output=m3u8"
    )
    #expect(
        account.playlistURL(type: "m3u", output: nil).absoluteString
            == "http://panel.example:8080/get.php?username=johndoe&password=s3cret&type=m3u"
    )
    #expect(account.xmltvURL.absoluteString == "http://panel.example:8080/xmltv.php?username=johndoe&password=s3cret")
}

@Test func buildsStreamURLs() {
    #expect(account.liveURL(streamID: 10234).absoluteString == "http://panel.example:8080/live/johndoe/s3cret/10234.m3u8")
    #expect(account.liveURL(streamID: 10234, containerExtension: "ts").absoluteString == "http://panel.example:8080/live/johndoe/s3cret/10234.ts")
    #expect(account.liveURL(streamID: 10234, containerExtension: nil).absoluteString == "http://panel.example:8080/live/johndoe/s3cret/10234")
    #expect(account.movieURL(streamID: 55120, containerExtension: "mkv").absoluteString == "http://panel.example:8080/movie/johndoe/s3cret/55120.mkv")
    #expect(account.episodeURL(episodeID: 90311, containerExtension: "mp4").absoluteString == "http://panel.example:8080/series/johndoe/s3cret/90311.mp4")
}

@Test func buildsCatchUpURLsInTheZoneItIsGiven() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC

    #expect(
        account.timeshiftURL(streamID: 10234, start: start, minutes: 62).absoluteString
            == "http://panel.example:8080/timeshift/johndoe/s3cret/62/2023-11-14:22-13/10234.m3u8"
    )

    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    #expect(
        account.timeshiftURL(streamID: 10234, start: start, minutes: 62, containerExtension: "ts", timeZone: tokyo).absoluteString
            == "http://panel.example:8080/timeshift/johndoe/s3cret/62/2023-11-15:07-13/10234.ts"
    )
    #expect(
        account.timeshiftQueryURL(streamID: 10234, start: start, minutes: 62).absoluteString
            == "http://panel.example:8080/streaming/timeshift.php?username=johndoe&password=s3cret&stream=10234&start=2023-11-14%3A22-13&duration=62"
    )
}

@Test func theLinksItBuildsAreTheOnesM3UKitReads() throws {
    let live = try #require(XtreamStreamURL(url: account.liveURL(streamID: 10234)))
    #expect(live.kind == .live)
    #expect(live.streamID == 10234)
    #expect(live.username == "johndoe")
    #expect(live.password == "s3cret")

    let movie = try #require(XtreamStreamURL(url: account.movieURL(streamID: 55120, containerExtension: "mkv")))
    #expect(movie.kind == .movie)
    #expect(movie.containerExtension == "mkv")

    let episode = try #require(XtreamStreamURL(url: account.episodeURL(episodeID: 90311, containerExtension: "mp4")))
    #expect(episode.kind == .series)

    let replay = try #require(XtreamStreamURL(url: account.timeshiftURL(streamID: 10234, start: .now, minutes: 30)))
    #expect(replay.kind == .timeshift)
    #expect(replay.streamID == 10234)

    // A password with a slash in it still reads back whole.
    let odd = XtreamAccount(baseURL: account.baseURL, username: "a@b", password: "p/w+ d")
    let parsed = try #require(XtreamStreamURL(url: odd.liveURL(streamID: 1)))
    #expect(parsed.username == "a@b")
    #expect(parsed.password == "p/w+ d")
}
