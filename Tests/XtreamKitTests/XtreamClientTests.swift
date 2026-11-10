import Foundation
import Testing
@testable import XtreamKit

// MARK: - A session that answers from the test

private struct StubResponse: Sendable {
    var status = 200
    var body: Data

    init(status: Int = 200, _ text: String) {
        self.status = status
        body = Data(text.utf8)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URL) -> StubResponse] = [:]
    nonisolated(unsafe) private static var userAgents: [String: String] = [:]

    static func userAgent(host: String) -> String? {
        lock.withLock { userAgents[host] }
    }

    static func register(host: String, _ handler: @escaping @Sendable (URL) -> StubResponse) {
        lock.withLock { handlers[host] = handler }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              let handler = Self.lock.withLock({ Self.handlers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        if let userAgent = request.value(forHTTPHeaderField: "User-Agent") {
            Self.lock.withLock { Self.userAgents[host] = userAgent }
        }

        let response = handler(url)
        // Answered a moment later, so that requests can be seen overlapping.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { [self] in
            let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URL] = []
    private var inFlight = 0
    private(set) var peak = 0

    func record(_ url: URL) {
        lock.withLock {
            requests.append(url)
            inFlight += 1
            peak = max(peak, inFlight)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { [self] in
            lock.withLock { inFlight -= 1 }
        }
    }

    var urls: [URL] { lock.withLock { requests } }

    func count(where predicate: (URL) -> Bool) -> Int { urls.filter(predicate).count }
}

private func makeClient(
    retryDelays: [Duration] = [],
    maxConcurrentRequests: Int = 4,
    temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    _ handler: @escaping @Sendable (URL) -> StubResponse
) -> XtreamClient {
    let host = "panel-\(UUID().uuidString.lowercased().prefix(8)).example"
    StubURLProtocol.register(host: host, handler)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let account = XtreamAccount(baseURL: URL(string: "http://\(host)")!, username: "u", password: "p")
    return XtreamClient(
        account: account,
        session: URLSession(configuration: configuration),
        configuration: .init(
            maxConcurrentRequests: maxConcurrentRequests,
            retryDelays: retryDelays,
            temporaryDirectory: temporaryDirectory
        )
    )
}

private func makeEmptyDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xtream-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func files(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
}

private func action(of url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
}

private func parameter(_ name: String, of url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

// MARK: - Account

@Test func readsTheAccount() async throws {
    let client = makeClient { _ in
        StubResponse(#"{"user_info":{"username":"u","auth":1,"status":"Active","max_connections":"2"},"server_info":{"timezone":"UTC"}}"#)
    }

    let info = try await client.accountInfo()
    #expect(info.maxConnections == 2)
    try info.requireUsable()
}

@Test(arguments: [
    (200, "false", XtreamError.accountRejected),
    (200, "", XtreamError.accountRejected),
    (200, "null", XtreamError.accountRejected),
    (200, "{}", XtreamError.accountRejected),
    (200, "<html><body>Welcome</body></html>", XtreamError.panelReturnedHTML),
    (200, "\n  <!DOCTYPE html>", XtreamError.panelReturnedHTML),
    (401, "", XtreamError.accountRejected),
    (403, "", XtreamError.accountRejected),
    (404, "", XtreamError.unexpectedStatus(404)),
] as [(Int, String, XtreamError)])
private func mapsWhatAPanelSaysInPlaceOfAnAccount(_ status: Int, _ body: String, _ expected: XtreamError) async {
    let client = makeClient { _ in StubResponse(status: status, body) }
    await #expect(throws: expected) { try await client.accountInfo() }
}

@Test func returnsAnExpiredAccountsDetailsWithoutThrowing() async throws {
    let client = makeClient { _ in
        StubResponse(#"{"user_info":{"username":"u","auth":1,"status":"Expired","exp_date":"1600000000"}}"#)
    }

    let info = try await client.accountInfo()
    #expect(info.status == .expired)
    #expect(throws: XtreamError.accountExpired(Date(timeIntervalSince1970: 1_600_000_000))) { try info.requireUsable() }
}

@Test func reportsAServerThatCannotBeReached() async {
    // No handler is registered for this host, so the stub fails the request as an unreachable server would.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let client = XtreamClient(
        account: XtreamAccount(baseURL: URL(string: "http://nobody.example")!, username: "u", password: "p"),
        session: URLSession(configuration: configuration),
        configuration: .init(retryDelays: [])
    )

    do {
        _ = try await client.accountInfo()
        Issue.record("Expected the request to fail")
    } catch let error as XtreamError {
        guard case .panelUnreachable = error else {
            Issue.record("Expected panelUnreachable, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected an XtreamError, got \(error)")
    }
}

// MARK: - Retries

@Test func retriesAServerErrorAndThenSucceeds() async throws {
    let tally = Tally()
    let client = makeClient(retryDelays: [.zero, .zero]) { url in
        tally.record(url)
        return tally.urls.count < 3 ? StubResponse(status: 503, "") : StubResponse(#"{"user_info":{"auth":1,"status":"Active"}}"#)
    }

    let info = try await client.accountInfo()
    #expect(info.isAuthenticated)
    #expect(tally.urls.count == 3)
}

@Test func givesUpAfterTheConfiguredRetries() async {
    let tally = Tally()
    let client = makeClient(retryDelays: [.zero, .zero]) { url in
        tally.record(url)
        return StubResponse(status: 502, "")
    }

    await #expect(throws: XtreamError.unexpectedStatus(502)) { try await client.accountInfo() }
    #expect(tally.urls.count == 3)
}

@Test func doesNotRetryARefusal() async {
    let tally = Tally()
    let client = makeClient(retryDelays: [.zero, .zero]) { url in
        tally.record(url)
        return StubResponse(status: 404, "")
    }

    await #expect(throws: XtreamError.unexpectedStatus(404)) { try await client.accountInfo() }
    #expect(tally.urls.count == 1)
}

// MARK: - Lists

@Test func downloadsAndDecodesAList() async throws {
    let client = makeClient { url in
        #expect(action(of: url) == "get_live_streams")
        return StubResponse(#"[{"name":"A","stream_id":"1","category_id":"5"},{"name":"B","stream_id":2},{"name":"bad"}]"#)
    }

    let list = try await client.liveStreams()
    #expect(list.items.map(\.streamID) == [1, 2])
    #expect(list.droppedCount == 1)
}

@Test(arguments: [
    (200, #"[{"name":"A","stream_id":1}]"#),
    (200, "false"),
    (200, "<html></html>"),
    (200, "[truncated"),
    (403, ""),
    (500, "oops"),
] as [(Int, String)])
private func leavesNoDownloadBehind(_ status: Int, _ body: String) async throws {
    let directory = try makeEmptyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = makeClient(temporaryDirectory: directory) { _ in StubResponse(status: status, body) }

    _ = try? await client.liveStreams(categoryID: "1")

    #expect(try files(in: directory).isEmpty)
}

@Test func leavesNoDownloadBehindWhenFallingBackToCategories() async throws {
    let directory = try makeEmptyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = makeClient(temporaryDirectory: directory) { url in
        switch (action(of: url), parameter("category_id", of: url)) {
        case ("get_live_streams", nil): StubResponse(status: 500, "")
        case ("get_live_categories", _): StubResponse(#"[{"category_id":"1","category_name":"A"}]"#)
        default: StubResponse(#"[{"name":"A","stream_id":1}]"#)
        }
    }

    _ = try await client.liveStreams()

    #expect(try files(in: directory).isEmpty)
}

@Test func asksForOneCategory() async throws {
    let client = makeClient { url in
        #expect(parameter("category_id", of: url) == "30")
        return StubResponse(#"[{"name":"Movie","stream_id":9}]"#)
    }

    let list = try await client.vodStreams(categoryID: "30")
    #expect(list.items.map(\.streamID) == [9])
}

@Test func readsCategories() async throws {
    let client = makeClient { url in
        #expect(action(of: url) == "get_series_categories")
        return StubResponse(#"[{"category_id":"7","category_name":"Drama","parent_id":0}]"#)
    }

    let categories = try await client.categories(.series)
    #expect(categories.map(\.name) == ["Drama"])
}

@Test func fallsBackToCategoriesWhenTheWholeListFails() async throws {
    let tally = Tally()
    let client = makeClient { url in
        tally.record(url)
        switch (action(of: url), parameter("category_id", of: url)) {
        case ("get_vod_streams", nil):
            return StubResponse(status: 500, "")
        case ("get_vod_categories", _):
            return StubResponse(#"[{"category_id":"1","category_name":"A"},{"category_id":"2","category_name":"B"}]"#)
        case ("get_vod_streams", "1"):
            return StubResponse(#"[{"name":"One","stream_id":1},{"name":"Both","stream_id":3}]"#)
        case ("get_vod_streams", "2"):
            return StubResponse(#"[{"name":"Two","stream_id":2},{"name":"Both","stream_id":3},{"name":"bad"}]"#)
        default:
            return StubResponse(status: 404, "")
        }
    }

    let list = try await client.vodStreams()

    // In category order, and a movie in two categories only once.
    #expect(list.items.map(\.streamID) == [1, 3, 2])
    #expect(list.droppedCount == 1)
}

@Test func keepsToTheConfiguredNumberOfRequestsAtOnce() async throws {
    let tally = Tally()
    let categories = (1...12).map { #"{"category_id":"\#($0)","category_name":"C\#($0)"}"# }.joined(separator: ",")
    let client = makeClient(maxConcurrentRequests: 3) { url in
        tally.record(url)
        switch (action(of: url), parameter("category_id", of: url)) {
        case ("get_live_streams", nil): return StubResponse(status: 500, "")
        case ("get_live_categories", _): return StubResponse("[\(categories)]")
        case let ("get_live_streams", id?): return StubResponse(#"[{"name":"C","stream_id":\#(id)}]"#)
        default: return StubResponse(status: 404, "")
        }
    }

    let list = try await client.liveStreams()

    #expect(list.items.count == 12)
    #expect(tally.peak <= 3)
    #expect(tally.peak > 1)
}

@Test func doesNotSplitByCategoryWhenTheAccountIsRejected() async {
    let tally = Tally()
    let client = makeClient { url in
        tally.record(url)
        return StubResponse(status: 403, "")
    }

    await #expect(throws: XtreamError.accountRejected) { try await client.liveStreams() }
    #expect(tally.urls.count == 1)
}

@Test func reportsAnActionThePanelDoesNotImplement() async {
    let client = makeClient { _ in StubResponse("false") }
    await #expect(throws: XtreamError.unsupportedAction("get_series")) { try await client.series() }
}

// MARK: - Details and guide

@Test func readsMovieInfo() async throws {
    let client = makeClient { url in
        #expect(action(of: url) == "get_vod_info")
        #expect(parameter("vod_id", of: url) == "55120")
        return StubResponse(#"{"info":{"name":"Dune","plot":"Paul"},"movie_data":{"stream_id":55120,"name":"Dune"}}"#)
    }

    let info = try await client.vodInfo(id: 55120)
    #expect(info.info?.plot == "Paul")
}

@Test func readsSeriesInfo() async throws {
    let client = makeClient { url in
        #expect(action(of: url) == "get_series_info")
        #expect(parameter("series_id", of: url) == "901")
        return StubResponse(#"{"seasons":[],"info":{"name":"Show"},"episodes":{"1":[{"id":"5","episode_num":"1","title":"Pilot"}]}}"#)
    }

    let show = try await client.seriesInfo(id: 901)
    #expect(show.episodes.map(\.id) == [5])
}

@Test func givesDetailsAsThePanelSentThem() async throws {
    let series = #"{"seasons":[],"info":{"name":"Show"},"episodes":{"1":[{"id":"5","episode_num":"1","title":"Pilot"}]}}"#
    let movie = #"{"info":{"name":"Dune","plot":"Paul"},"movie_data":{"stream_id":55120,"name":"Dune"}}"#
    let client = makeClient { url in
        switch action(of: url) {
        case "get_series_info": StubResponse(series)
        case "get_vod_info": StubResponse(movie)
        default: StubResponse(status: 404, "")
        }
    }

    let seriesData = try await client.seriesInfoData(id: 901)
    #expect(String(decoding: seriesData, as: UTF8.self) == series)
    #expect(try JSONDecoder().decode(XtreamSeriesInfo.self, from: seriesData).episodes.map(\.id) == [5])

    let movieData = try await client.vodInfoData(id: 55120)
    #expect(try JSONDecoder().decode(XtreamVODInfo.self, from: movieData).info?.plot == "Paul")
}

@Test func rawDetailsStillTellRefusalsApart() async {
    let client = makeClient { _ in StubResponse("false") }
    await #expect(throws: XtreamError.unsupportedAction("get_series_info")) { try await client.seriesInfoData(id: 1) }
    await #expect(throws: XtreamError.unsupportedAction("get_vod_info")) { try await client.vodInfoData(id: 1) }
}

@Test func readsTheGuideInBothShapes() async throws {
    let client = makeClient { url in
        switch action(of: url) {
        case "get_short_epg":
            #expect(parameter("stream_id", of: url) == "10234")
            #expect(parameter("limit", of: url) == "2")
            return StubResponse(#"{"epg_listings":[{"id":"1","title":"Tm93","start_timestamp":"1700000000","stop_timestamp":"1700003600"}]}"#)
        case "get_simple_data_table":
            return StubResponse(#"{"epg_listings":[{"id":"2","title":"Past","start_timestamp":"1699990000","stop_timestamp":"1699993600","has_archive":1,"now_playing":0}]}"#)
        default:
            return StubResponse(status: 404, "")
        }
    }

    let short = try await client.shortEPG(streamID: 10234, limit: 2)
    #expect(short.items.map(\.title) == ["Now"])

    let table = try await client.simpleDataTable(streamID: 10234)
    #expect(table.items.first?.hasArchive == true)
}

@Test func sendsTheConfiguredUserAgentOnlyWhenOneIsSet() async throws {
    let host = "panel-\(UUID().uuidString.lowercased().prefix(8)).example"
    StubURLProtocol.register(host: host) { _ in StubResponse(#"{"user_info":{"auth":1,"status":"Active"}}"#) }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let account = XtreamAccount(baseURL: URL(string: "http://\(host)")!, username: "u", password: "p")

    let plain = XtreamClient(account: account, session: URLSession(configuration: configuration))
    _ = try await plain.accountInfo()
    #expect(StubURLProtocol.userAgent(host: host) == nil)

    let pinned = XtreamClient(
        account: account,
        session: URLSession(configuration: configuration),
        configuration: .init(userAgent: "IPTV/1.0")
    )
    _ = try await pinned.accountInfo()
    #expect(StubURLProtocol.userAgent(host: host) == "IPTV/1.0")
}
