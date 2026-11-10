import Foundation

/// A line on an Xtream Codes panel: where it is and who it belongs to. Builds every URL the panel serves.
///
/// The username and password are held as the panel sees them, decoded. They are encoded again for each URL, so a
/// password with `+`, `/` or `&` in it works in a query and in a stream path alike.
public struct XtreamAccount: Hashable, Sendable {
    /// `scheme://host:port`, plus the folder a panel mounted below its host's root is in. No trailing slash.
    public var baseURL: URL
    public var username: String
    public var password: String

    public init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    /// Reads an account out of a panel link: `get.php`, `player_api.php`, `panel_api.php` or `xmltv.php` with
    /// `username` and `password` in its query.
    public init?(link: URL) {
        guard var components = URLComponents(url: link, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else { return nil }

        var path = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let file = path.last, Self.panelFiles.contains(file.lowercased()) else { return nil }
        path.removeLast()

        var credentials: [String: String] = [:]
        for item in components.percentEncodedQueryItems ?? [] {
            guard let value = item.value else { continue }
            // A query is form-encoded: `+` is a space, which the panel reads before it checks the password.
            credentials[item.name.lowercased()] = value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
        }
        guard let username = credentials["username"], username.isEmpty == false,
              let password = credentials["password"], password.isEmpty == false else { return nil }

        components.percentEncodedPath = path.isEmpty ? "" : "/" + path.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else { return nil }

        self.init(baseURL: baseURL, username: username, password: password)
    }

    public init?(link: String) {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(link: url)
    }

    /// Builds an account from what a person types: an address that may lack `http://`, may carry a port, and may
    /// have been pasted with a panel file on the end.
    public init?(server: String, username: String, password: String) {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false, username.isEmpty == false, password.isEmpty == false else { return nil }
        if text.contains("://") == false { text = "http://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else { return nil }

        var path = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let file = path.last, Self.panelFiles.contains(file.lowercased()) { path.removeLast() }

        components.percentEncodedPath = path.isEmpty ? "" : "/" + path.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else { return nil }

        self.init(baseURL: baseURL, username: username, password: password)
    }

    private static let panelFiles: Set<String> = ["get.php", "player_api.php", "panel_api.php", "xmltv.php", "enigma2.php"]

    // MARK: - API and files

    /// `player_api.php`, with no action for the account itself.
    public func playerAPIURL(action: String? = nil, parameters: [(name: String, value: String)] = []) -> URL {
        var items = [("username", username), ("password", password)]
        if let action { items.append(("action", action)) }
        items += parameters.map { ($0.name, $0.value) }
        return url("player_api.php?" + Self.query(items))
    }

    /// The playlist a panel exports. `m3u_plus` carries logos and groups; `output` picks the live container.
    public func playlistURL(type: String = "m3u_plus", output: String? = "m3u8") -> URL {
        var items = [("username", username), ("password", password), ("type", type)]
        if let output { items.append(("output", output)) }
        return url("get.php?" + Self.query(items))
    }

    public var xmltvURL: URL {
        url("xmltv.php?" + Self.query([("username", username), ("password", password)]))
    }

    // MARK: - Streams

    /// A live stream. `m3u8` is what AVPlayer plays; a panel's `ts` is raw transport stream.
    public func liveURL(streamID: Int, containerExtension: String? = "m3u8") -> URL {
        streamURL(kind: "live", id: streamID, containerExtension: containerExtension)
    }

    public func movieURL(streamID: Int, containerExtension: String) -> URL {
        streamURL(kind: "movie", id: streamID, containerExtension: containerExtension)
    }

    /// An episode, by the episode's own ID and not the series'.
    public func episodeURL(episodeID: Int, containerExtension: String) -> URL {
        streamURL(kind: "series", id: episodeID, containerExtension: containerExtension)
    }

    /// Catch-up in the path form: `/timeshift/{user}/{pass}/{minutes}/{YYYY-MM-DD:HH-MM}/{id}.{ext}`. Panels differ
    /// on whether `start` is in their own time zone or UTC, so the caller chooses.
    public func timeshiftURL(
        streamID: Int,
        start: Date,
        minutes: Int,
        containerExtension: String? = "m3u8",
        timeZone: TimeZone = .gmt
    ) -> URL {
        let file = containerExtension.map { "\(streamID).\($0)" } ?? "\(streamID)"
        return url("timeshift/\(Self.encode(username))/\(Self.encode(password))/\(minutes)/\(Self.timeshiftStart(start, in: timeZone))/\(file)")
    }

    /// Catch-up in the query form some panels serve instead.
    public func timeshiftQueryURL(streamID: Int, start: Date, minutes: Int, timeZone: TimeZone = .gmt) -> URL {
        url("streaming/timeshift.php?" + Self.query([
            ("username", username),
            ("password", password),
            ("stream", String(streamID)),
            ("start", Self.timeshiftStart(start, in: timeZone)),
            ("duration", String(minutes)),
        ]))
    }

    // MARK: - Building

    private func streamURL(kind: String, id: Int, containerExtension: String?) -> URL {
        let file = containerExtension.map { "\(id).\($0)" } ?? String(id)
        return url("\(kind)/\(Self.encode(username))/\(Self.encode(password))/\(file)")
    }

    private func url(_ relative: String) -> URL {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        guard let url = URL(string: base + "/" + relative) else {
            preconditionFailure("A panel URL built from a valid base and encoded parts can't be invalid: \(relative)")
        }
        return url
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func query(_ items: [(String, String)]) -> String {
        items.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
    }

    private static func timeshiftStart(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd:HH-mm"
        return formatter.string(from: date)
    }
}
