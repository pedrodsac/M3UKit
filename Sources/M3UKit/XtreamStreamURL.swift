import Foundation

/// The parts of a stream URL in an Xtream Codes (or XUI) panel's own scheme.
///
/// The panel puts a stream's kind, its credentials and its numeric ID in the path, so a link says what it is
/// without any help from the playlist's group names:
///
/// - `/live/{user}/{pass}/{id}.{ts|m3u8}`, or the short form `/{user}/{pass}/{id}` that `get.php` writes
/// - `/movie/{user}/{pass}/{id}.{container}`
/// - `/series/{user}/{pass}/{episodeID}.{container}`
/// - `/timeshift/{user}/{pass}/{minutes}/{YYYY-MM-DD:HH-MM}/{id}.{ts|m3u8}`
///
/// XUI's tokenised links (`/play/{token}/ts`) carry no ID; it is in the entry's `xui-id` attribute instead.
public struct XtreamStreamURL: Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case live
        case movie
        case series
        case timeshift
    }

    public var kind: Kind
    /// The stream's ID, or for a series link the episode's ID.
    public var streamID: Int
    public var username: String
    public var password: String
    /// The extension of the last path component, lowercased: `ts`, `m3u8`, `mkv`. Nil when the link has none.
    public var containerExtension: String?

    public init(kind: Kind, streamID: Int, username: String, password: String, containerExtension: String? = nil) {
        self.kind = kind
        self.streamID = streamID
        self.username = username
        self.password = password
        self.containerExtension = containerExtension
    }

    /// Reads a link in the panel's scheme, or returns nil when it isn't one.
    public init?(url: URL) {
        self.init(parts: URLParts(url))
    }

    init?(parts: URLParts) {
        let segments = parts.pathSegments
        guard segments.isEmpty == false else { return nil }

        if segments.count >= 4, let kind = Self.marker(segments[segments.count - 4]),
           let stream = Self.parseStream(segments[segments.count - 1]) {
            self.init(
                kind: kind,
                streamID: stream.id,
                username: Self.decoded(segments[segments.count - 3]),
                password: Self.decoded(segments[segments.count - 2]),
                containerExtension: stream.containerExtension
            )
            return
        }

        if segments.count >= 6, segments[segments.count - 6] == "timeshift",
           let stream = Self.parseStream(segments[segments.count - 1]) {
            self.init(
                kind: .timeshift,
                streamID: stream.id,
                username: Self.decoded(segments[segments.count - 5]),
                password: Self.decoded(segments[segments.count - 4]),
                containerExtension: stream.containerExtension
            )
            return
        }

        // The short form is a live link: exactly three segments, and the last is a number that is at most a
        // `.ts` or `.m3u8` away from bare. The first can't be one of the words other schemes put there.
        if segments.count == 3, Self.reservedFirstSegments.contains(segments[0]) == false,
           let stream = Self.parseStream(segments[2]),
           stream.containerExtension == nil || stream.containerExtension == "ts" || stream.containerExtension == "m3u8" {
            self.init(
                kind: .live,
                streamID: stream.id,
                username: Self.decoded(segments[0]),
                password: Self.decoded(segments[1]),
                containerExtension: stream.containerExtension
            )
            return
        }

        return nil
    }

    private static let reservedFirstSegments: Set<String> = [
        "live", "movie", "series", "vod", "radio", "play", "hls", "hlsr", "timeshift", "streaming",
    ]

    private static func marker(_ segment: String) -> Kind? {
        switch segment {
        case "live": .live
        case "movie": .movie
        case "series": .series
        default: nil
        }
    }

    /// `12345.mkv` → (12345, "mkv"), `12345` → (12345, nil). Anything else isn't a stream.
    private static func parseStream(_ component: String) -> (id: Int, containerExtension: String?)? {
        let pieces = component.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = pieces.first, first.isEmpty == false, first.allSatisfy(\.isASCIINumber),
              let id = Int(first) else { return nil }

        let containerExtension = pieces.count == 2 ? pieces[1].lowercased() : nil
        if let containerExtension, containerExtension.isEmpty || containerExtension.contains(".") { return nil }
        return (id, containerExtension)
    }

    private static func decoded(_ segment: String) -> String {
        segment.removingPercentEncoding ?? segment
    }
}

/// A URL split on the text it was written with, because `URL.path` decodes `%2F` into a separator and would turn a
/// password that contains one into two segments.
struct URLParts {
    var pathSegments: [String]
    /// The text after `#`, which XUI uses to carry a VOD link's container (`#.mp4`).
    var fragment: String?

    init(_ url: URL) {
        let string = url.absoluteString
        var rest = Substring(string)

        if let fragmentStart = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: fragmentStart)...])
            rest = rest[..<fragmentStart]
        }

        if let queryStart = rest.firstIndex(of: "?") {
            rest = rest[..<queryStart]
        }

        guard let schemeEnd = rest.range(of: "://") else {
            pathSegments = []
            return
        }

        let afterAuthority = rest[schemeEnd.upperBound...]
        guard let pathStart = afterAuthority.firstIndex(of: "/") else {
            pathSegments = []
            return
        }

        pathSegments = afterAuthority[pathStart...].split(separator: "/").map { String($0) }
    }
}

private extension Character {
    var isASCIINumber: Bool { isASCII && isNumber }
}
