import Foundation

public enum XtreamCatalogKind: String, CaseIterable, Sendable {
    case live
    case vod
    case series

    var categoriesAction: String { "get_\(rawValue)_categories" }

    var streamsAction: String {
        switch self {
        case .live: "get_live_streams"
        case .vod: "get_vod_streams"
        case .series: "get_series"
        }
    }
}

/// Talks to a panel's `player_api.php`.
///
/// Panels throttle and sometimes ban bursts, so at most `maxConcurrentRequests` run at once. Lists can hold hundreds
/// of thousands of items, so they are downloaded to a file and decoded from a memory-mapped view of it. When the
/// panel can't deliver a whole list (a timeout, an overloaded server, a truncated body), it's fetched category by
/// category instead.
public actor XtreamClient {
    public struct Configuration: Sendable {
        public var maxConcurrentRequests: Int
        /// Waits before each retry of a request that failed in a way that may pass. Empty for no retries.
        public var retryDelays: [Duration]
        public var userAgent: String?
        public var requestTimeout: TimeInterval
        public var listTimeout: TimeInterval
        /// Where a list is kept while it is decoded. Each file is deleted as soon as the list has been read.
        public var temporaryDirectory: URL

        public init(
            maxConcurrentRequests: Int = 4,
            retryDelays: [Duration] = [.milliseconds(500), .seconds(2)],
            userAgent: String? = nil,
            requestTimeout: TimeInterval = 30,
            listTimeout: TimeInterval = 180,
            temporaryDirectory: URL = FileManager.default.temporaryDirectory
        ) {
            self.maxConcurrentRequests = max(1, maxConcurrentRequests)
            self.retryDelays = retryDelays
            self.userAgent = userAgent
            self.requestTimeout = requestTimeout
            self.listTimeout = listTimeout
            self.temporaryDirectory = temporaryDirectory
        }
    }

    public nonisolated let account: XtreamAccount

    private let session: URLSession
    private let configuration: Configuration
    private let limiter: RequestLimiter

    public init(account: XtreamAccount, session: URLSession? = nil, configuration: Configuration = Configuration()) {
        self.account = account
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.configuration = configuration
        limiter = RequestLimiter(limit: configuration.maxConcurrentRequests)
    }

    // MARK: - Account

    /// The line's `user_info` and `server_info`. A line that's expired, banned or disabled still returns its details;
    /// call `requireUsable()` on them to turn that into an error.
    public func accountInfo() async throws -> XtreamAccountInfo {
        let data = try await fetch(account.playerAPIURL(), timeout: configuration.requestTimeout)
        let body = try Self.checkedBody(data, action: nil)

        do {
            return try JSONDecoder().decode(XtreamAccountResponse.self, from: body).info
        } catch DecodingError.keyNotFound, DecodingError.typeMismatch {
            // Without `user_info`, the panel is saying no, in a shape other than the usual one.
            throw XtreamError.accountRejected
        } catch {
            throw XtreamError.decodingFailed(String(describing: error))
        }
    }

    // MARK: - Catalog

    public func categories(_ kind: XtreamCatalogKind) async throws -> [XtreamCategory] {
        let url = account.playerAPIURL(action: kind.categoriesAction)
        let data = try await fetch(url, timeout: configuration.requestTimeout)
        return try Self.decodeList(XtreamCategory.self, from: data, action: kind.categoriesAction).items
    }

    public func liveStreams(categoryID: String? = nil) async throws -> XtreamList<XtreamLiveStream> {
        try await streams(.live, categoryID: categoryID, id: \.streamID)
    }

    public func vodStreams(categoryID: String? = nil) async throws -> XtreamList<XtreamVODStream> {
        try await streams(.vod, categoryID: categoryID, id: \.streamID)
    }

    /// One entry per show. A show's episodes come from `seriesInfo(id:)`.
    public func series(categoryID: String? = nil) async throws -> XtreamList<XtreamSeries> {
        try await streams(.series, categoryID: categoryID) { $0.seriesID ?? 0 }
    }

    // MARK: - Details

    public func vodInfo(id: Int) async throws -> XtreamVODInfo {
        let data = try await fetch(
            account.playerAPIURL(action: "get_vod_info", parameters: [("vod_id", String(id))]),
            timeout: configuration.requestTimeout
        )
        return try Self.decodeObject(XtreamVODInfo.self, from: data, action: "get_vod_info")
    }

    /// `get_vod_info` as the panel sent it, after the checks every answer gets, for an app that keeps the answer and
    /// reads it again later: a decoder fix then improves what is already stored. Decode it with `XtreamVODInfo`.
    public func vodInfoData(id: Int) async throws -> Data {
        let data = try await fetch(
            account.playerAPIURL(action: "get_vod_info", parameters: [("vod_id", String(id))]),
            timeout: configuration.requestTimeout
        )
        return try Self.checkedBody(data, action: "get_vod_info")
    }

    /// `get_series_info` as the panel sent it. Decode it with `XtreamSeriesInfo`.
    public func seriesInfoData(id: Int) async throws -> Data {
        let data = try await fetch(
            account.playerAPIURL(action: "get_series_info", parameters: [("series_id", String(id))]),
            timeout: configuration.requestTimeout
        )
        return try Self.checkedBody(data, action: "get_series_info")
    }

    public func seriesInfo(id: Int) async throws -> XtreamSeriesInfo {
        let data = try await fetch(
            account.playerAPIURL(action: "get_series_info", parameters: [("series_id", String(id))]),
            timeout: configuration.requestTimeout
        )
        return try Self.decodeObject(XtreamSeriesInfo.self, from: data, action: "get_series_info")
    }

    // MARK: - Guide

    /// The next few programmes of a channel, which is what a now/next row needs.
    public func shortEPG(streamID: Int, limit: Int = 4) async throws -> XtreamList<XtreamEPGListing> {
        try await epg(action: "get_short_epg", streamID: streamID, extra: [("limit", String(limit))])
    }

    /// A channel's whole schedule, past programmes included, with which of them can be replayed.
    public func simpleDataTable(streamID: Int) async throws -> XtreamList<XtreamEPGListing> {
        try await epg(action: "get_simple_data_table", streamID: streamID, extra: [])
    }

    private func epg(action: String, streamID: Int, extra: [(name: String, value: String)]) async throws -> XtreamList<XtreamEPGListing> {
        let url = account.playerAPIURL(action: action, parameters: [("stream_id", String(streamID))] + extra)
        let body = try Self.checkedBody(try await fetch(url, timeout: configuration.requestTimeout), action: action)

        do {
            return try JSONDecoder().decode(XtreamEPGResponse.self, from: body).listings
        } catch {
            throw XtreamError.decodingFailed(String(describing: error))
        }
    }

    // MARK: - Lists

    private func streams<Item: Decodable & Sendable>(
        _ kind: XtreamCatalogKind,
        categoryID: String?,
        id: @escaping @Sendable (Item) -> Int
    ) async throws -> XtreamList<Item> {
        if let categoryID {
            return try await downloadList(Item.self, kind: kind, categoryID: categoryID)
        }

        do {
            return try await downloadList(Item.self, kind: kind, categoryID: nil)
        } catch let error as XtreamError where Self.canSplitByCategory(error) {
            return try await streamsByCategory(kind, id: id)
        }
    }

    private func streamsByCategory<Item: Decodable & Sendable>(
        _ kind: XtreamCatalogKind,
        id: @escaping @Sendable (Item) -> Int
    ) async throws -> XtreamList<Item> {
        let categories = try await categories(kind)

        // The limiter keeps these to the configured number of requests at once.
        let lists = try await withThrowingTaskGroup(of: (Int, XtreamList<Item>).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask { (index, try await self.downloadList(Item.self, kind: kind, categoryID: category.categoryID)) }
            }

            var results: [(Int, XtreamList<Item>)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        // A stream in two categories is listed by both.
        var seen: Set<Int> = []
        var merged: [Item] = []
        var dropped = 0
        for list in lists {
            dropped += list.droppedCount
            for item in list.items where seen.insert(id(item)).inserted {
                merged.append(item)
            }
        }

        return XtreamList(items: merged, droppedCount: dropped)
    }

    private func downloadList<Item: Decodable & Sendable>(
        _ type: Item.Type,
        kind: XtreamCatalogKind,
        categoryID: String?
    ) async throws -> XtreamList<Item> {
        let parameters = categoryID.map { [(name: "category_id", value: $0)] } ?? []
        let url = account.playerAPIURL(action: kind.streamsAction, parameters: parameters)
        let fileURL = try await download(url, timeout: configuration.listTimeout)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let action = kind.streamsAction
        return try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: fileURL, options: .alwaysMapped)
            return try Self.decodeList(Item.self, from: data, action: action)
        }.value
    }

    private static func canSplitByCategory(_ error: XtreamError) -> Bool {
        switch error {
        case .panelUnreachable, .decodingFailed, .emptyResponse: true
        case let .unexpectedStatus(status): status >= 500 || status == 408 || status == 429
        default: false
        }
    }

    // MARK: - Requests

    private func fetch(_ url: URL, timeout: TimeInterval) async throws -> Data {
        try await perform(url, timeout: timeout) { request in
            let (data, response) = try await self.session.data(for: request)
            return (data, response)
        }
    }

    private func download(_ url: URL, timeout: TimeInterval) async throws -> URL {
        let directory = configuration.temporaryDirectory
        return try await perform(url, timeout: timeout) { request in
            let (file, response) = try await self.session.download(for: request)

            // A refusal is checked before the file is kept, so it doesn't leave one behind.
            do {
                try Self.checkStatus(response)
                let kept = directory.appendingPathComponent("xtream-\(UUID().uuidString).json")
                try FileManager.default.moveItem(at: file, to: kept)
                return (kept, response)
            } catch {
                try? FileManager.default.removeItem(at: file)
                throw error
            }
        }
    }

    private func perform<Result: Sendable>(
        _ url: URL,
        timeout: TimeInterval,
        _ send: @Sendable (URLRequest) async throws -> (Result, URLResponse)
    ) async throws -> Result {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let userAgent = configuration.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        var attempt = 0
        while true {
            await limiter.acquire()
            let outcome: Swift.Result<Result, XtreamError>
            do {
                let (result, response) = try await send(request)
                try Self.checkStatus(response)
                outcome = .success(result)
            } catch let error as XtreamError {
                outcome = .failure(error)
            } catch let error as URLError where error.code == .cancelled {
                await limiter.release()
                throw CancellationError()
            } catch let error as URLError {
                outcome = .failure(.panelUnreachable(error.localizedDescription))
            } catch {
                await limiter.release()
                throw error
            }
            await limiter.release()

            switch outcome {
            case let .success(result):
                return result
            case let .failure(error):
                guard attempt < configuration.retryDelays.count, Self.isTransient(error) else { throw error }
                try await Task.sleep(for: configuration.retryDelays[attempt])
                attempt += 1
            }
        }
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) == false else { return }
        throw status == 401 || status == 403 ? XtreamError.accountRejected : XtreamError.unexpectedStatus(status)
    }

    private static func isTransient(_ error: XtreamError) -> Bool {
        switch error {
        case .panelUnreachable: true
        case let .unexpectedStatus(status): status >= 500 || status == 408 || status == 429
        default: false
        }
    }

    // MARK: - Reading bodies

    /// Turns what a panel says in place of data into the error it means. `false` is a refusal for the account call
    /// and an unimplemented action for the rest.
    static func checkedBody(_ data: Data, action: String?) throws -> Data {
        let leading = data.prefix(256)
        let text = String(decoding: leading, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw action == nil ? XtreamError.accountRejected : XtreamError.emptyResponse
        }
        if text.hasPrefix("<") {
            throw XtreamError.panelReturnedHTML
        }
        if text == "false" || text == "null" {
            throw action.map(XtreamError.unsupportedAction) ?? XtreamError.accountRejected
        }
        return data
    }

    static func decodeList<Item: Decodable & Sendable>(_ type: Item.Type, from data: Data, action: String) throws -> XtreamList<Item> {
        let body = try checkedBody(data, action: action)
        do {
            return try XtreamList<Item>.decode(body)
        } catch {
            throw XtreamError.decodingFailed(String(describing: error))
        }
    }

    static func decodeObject<Value: Decodable>(_ type: Value.Type, from data: Data, action: String) throws -> Value {
        let body = try checkedBody(data, action: action)
        do {
            return try JSONDecoder().decode(Value.self, from: body)
        } catch {
            throw XtreamError.decodingFailed(String(describing: error))
        }
    }
}

/// Lets a fixed number of requests through at once.
private actor RequestLimiter {
    private var available: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = limit
    }

    func acquire() async {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    func release() {
        if waiting.isEmpty {
            available += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
