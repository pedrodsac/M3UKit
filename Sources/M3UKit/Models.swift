import Foundation

public struct Playlist: Codable, Hashable, Sendable {
    public var media: [Media]
    public var attributes: [String: String]
    public var tags: [PlaylistTag]
    public var playlistType: HLSPlaylistType?
    public var targetDuration: Double?
    public var mediaSequence: Int?
    public var hasEndList: Bool
    public var isExtended: Bool

    public init(
        media: [Media] = [],
        attributes: [String: String] = [:],
        tags: [PlaylistTag] = [],
        playlistType: HLSPlaylistType? = nil,
        targetDuration: Double? = nil,
        mediaSequence: Int? = nil,
        hasEndList: Bool = false,
        isExtended: Bool = false
    ) {
        self.media = media
        self.attributes = attributes
        self.tags = tags
        self.playlistType = playlistType
        self.targetDuration = targetDuration
        self.mediaSequence = mediaSequence
        self.hasEndList = hasEndList
        self.isExtended = isExtended
    }

    public var isLive: Bool {
        playlistType == nil && !hasEndList
    }

    /// Whether an XUI panel wrote the playlist, which it marks with `#EXT-X-SESSION-DATA:DATA-ID="com.xui.dev"`.
    public var isXUI: Bool {
        tags.contains { tag in
            guard tag.name == "EXT-X-SESSION-DATA" else { return false }
            return tag.attributes.normalizedValue(for: "DATA-ID") == "com.xui.dev"
        }
    }

    public var groups: [String: [Media]] {
        Dictionary(grouping: media) { $0.groupTitle ?? "" }
    }

    public var channels: [Media] {
        media.filter { $0.contentType == .live || $0.contentType == .radio }
    }
}

public struct Media: Codable, Hashable, Sendable {
    public var title: String
    public var url: URL
    public var duration: Double?
    public var attributes: [String: String]
    public var contentType: MediaContentType
    public var series: SeriesInfo?
    public var group: String?
    public var hls: MediaHLSMetadata
    /// Options declared with `#EXTVLCOPT:` lines that precede this entry, such as a pinned user agent,
    /// referrer, origin, or `network-caching`. Keys are stored as written and values have surrounding
    /// quotes removed.
    public var vlcOptions: [String: String]

    public init(
        title: String,
        url: URL,
        duration: Double? = nil,
        attributes: [String: String] = [:],
        contentType: MediaContentType = .other,
        series: SeriesInfo? = nil,
        group: String? = nil,
        hls: MediaHLSMetadata = MediaHLSMetadata(),
        vlcOptions: [String: String] = [:]
    ) {
        self.title = title
        self.url = url
        self.duration = duration
        self.attributes = attributes
        self.contentType = contentType
        self.series = series
        self.group = group
        self.hls = hls
        self.vlcOptions = vlcOptions
    }

    public var tvgID: String? { attributes.normalizedValue(for: "tvg-id") }
    public var tvgName: String? { attributes.normalizedValue(for: "tvg-name") }
    public var tvgLogo: URL? { attributes.normalizedURL(for: "tvg-logo") }
    public var tvgCountry: String? { attributes.normalizedValue(for: "tvg-country") }
    public var tvgLanguage: String? { attributes.normalizedValue(for: "tvg-language") }
    public var tvgType: String? { attributes.normalizedValue(for: "tvg-type") }
    public var tvgEPGID: String? { attributes.normalizedValue(for: "tvg-epgid") }
    public var tvgShift: String? { attributes.normalizedValue(for: "tvg-shift") }

    /// The stream's ID in an Xtream Codes panel: from its link (`/live/user/pass/123.m3u8`), or for XUI's
    /// tokenised links from the entry's `xui-id` attribute. Nil for a link that isn't a panel's.
    public var xtreamStreamID: Int? {
        if let stream = XtreamStreamURL(url: url) { return stream.streamID }
        return attributes.normalizedValue(for: "xui-id").flatMap { Int($0) }
    }
    public var groupTitle: String? { group ?? attributes.normalizedValue(for: "group-title") ?? attributes.normalizedValue(for: "group_id") }
    public var audioTracks: [String] {
        attributes.normalizedValue(for: "audio-track")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    /// The user agent pinned with `#EXTVLCOPT:http-user-agent=...`, if any.
    public var httpUserAgent: String? { vlcOptions.normalizedValue(for: "http-user-agent") }
    /// The referrer pinned with `#EXTVLCOPT:http-referrer=...`, if any.
    public var httpReferrer: String? { vlcOptions.normalizedValue(for: "http-referrer") }
    /// The origin pinned with `#EXTVLCOPT:http-origin=...`, if any.
    public var httpOrigin: String? { vlcOptions.normalizedValue(for: "http-origin") }

    /// The pinned user agent, referrer and origin expressed as HTTP request headers, ready to attach to a
    /// request. Empty when the entry declares none.
    public var httpHeaders: [String: String] {
        var headers: [String: String] = [:]
        if let httpUserAgent { headers["User-Agent"] = httpUserAgent }
        if let httpReferrer { headers["Referer"] = httpReferrer }
        if let httpOrigin { headers["Origin"] = httpOrigin }
        return headers
    }

    public func catchUpURL(
        startDate: Date,
        duration: TimeInterval,
        playlistAttributes: [String: String] = [:]
    ) -> URL? {
        let configuration = CatchUpConfiguration(mediaAttributes: attributes, playlistAttributes: playlistAttributes)
        return configuration?.url(for: url, startDate: startDate, duration: duration)
    }
}

public enum MediaContentType: String, Codable, Hashable, Sendable {
    case live
    case movie
    case series
    case radio
    case show
    case other
}

/// What `MediaClassifier` makes of an entry.
public struct MediaClassification: Hashable, Sendable {
    public var contentType: MediaContentType
    /// The show and episode the title names: from an episode marker (`S01E02`) whatever the kind, or for an episode
    /// whose title names it only by its air date (`Show - 5/11/2026`), from that date.
    public var series: SeriesInfo?

    public init(contentType: MediaContentType, series: SeriesInfo? = nil) {
        self.contentType = contentType
        self.series = series
    }
}

public enum HLSPlaylistType: String, Codable, Hashable, Sendable {
    case event = "EVENT"
    case vod = "VOD"
}

public struct SeriesInfo: Codable, Hashable, Sendable {
    public var name: String
    public var season: Int?
    public var episode: Int?
    /// The episode's own name, when the title carries one after the season and episode numbers.
    public var episodeTitle: String?
    /// The show's year, when the title carries one in brackets before the season and episode numbers.
    public var year: Int?
    /// An air date as the title wrote it (`05 05 2025`), for shows listed by date.
    public var airDate: String?

    public init(
        name: String,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        year: Int? = nil,
        airDate: String? = nil
    ) {
        self.name = name
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
        self.year = year
        self.airDate = airDate
    }
}

public struct MediaHLSMetadata: Codable, Hashable, Sendable {
    public var key: HLSKey?
    public var byteRange: ByteRange?
    public var map: HLSMap?
    public var hasDiscontinuity: Bool
    public var tags: [PlaylistTag]

    public init(
        key: HLSKey? = nil,
        byteRange: ByteRange? = nil,
        map: HLSMap? = nil,
        hasDiscontinuity: Bool = false,
        tags: [PlaylistTag] = []
    ) {
        self.key = key
        self.byteRange = byteRange
        self.map = map
        self.hasDiscontinuity = hasDiscontinuity
        self.tags = tags
    }
}

public struct HLSKey: Codable, Hashable, Sendable {
    public var method: String?
    public var uri: URL?
    public var iv: String?
    public var attributes: [String: String]

    public init(method: String? = nil, uri: URL? = nil, iv: String? = nil, attributes: [String: String] = [:]) {
        self.method = method
        self.uri = uri
        self.iv = iv
        self.attributes = attributes
    }
}

public struct HLSMap: Codable, Hashable, Sendable {
    public var uri: URL?
    public var byteRange: ByteRange?
    public var attributes: [String: String]

    public init(uri: URL? = nil, byteRange: ByteRange? = nil, attributes: [String: String] = [:]) {
        self.uri = uri
        self.byteRange = byteRange
        self.attributes = attributes
    }
}

public struct ByteRange: Codable, Hashable, Sendable {
    public var length: Int
    public var offset: Int?

    public init(length: Int, offset: Int? = nil) {
        self.length = length
        self.offset = offset
    }
}

public struct PlaylistTag: Codable, Hashable, Sendable {
    public var name: String
    public var value: String?
    public var attributes: [String: String]

    public init(name: String, value: String? = nil, attributes: [String: String] = [:]) {
        self.name = name
        self.value = value
        self.attributes = attributes
    }
}

public enum CatchUpMode: String, Codable, Hashable, Sendable {
    case `default`
    case append
    case shift
    case flussonic
    case xtream
}

public struct CatchUpConfiguration: Codable, Hashable, Sendable {
    public var mode: CatchUpMode
    public var days: Int?
    public var source: String?

    public init?(mediaAttributes: [String: String], playlistAttributes: [String: String] = [:]) {
        let attributes = playlistAttributes.merging(mediaAttributes) { _, mediaValue in mediaValue }
        guard let rawMode = attributes.normalizedValue(for: "catchup")?.lowercased(),
              let mode = CatchUpMode(rawValue: rawMode) else {
            return nil
        }

        self.mode = mode
        self.days = attributes.normalizedValue(for: "catchup-days").flatMap(Int.init)
        self.source = attributes.normalizedValue(for: "catchup-source")
    }

    public init(mode: CatchUpMode, days: Int? = nil, source: String? = nil) {
        self.mode = mode
        self.days = days
        self.source = source
    }

    public func url(for liveURL: URL, startDate: Date, duration: TimeInterval) -> URL? {
        let timestamp = Int(startDate.timeIntervalSince1970)
        let duration = Int(duration)

        switch mode {
        case .default:
            guard let source else { return nil }
            return URL(string: liveURL.absoluteString + render(source, timestamp: timestamp, duration: duration))
        case .append:
            guard let source else { return nil }
            return URL(string: liveURL.absoluteString + render(source, timestamp: timestamp, duration: duration))
        case .shift:
            guard let source else { return nil }
            return URL(string: render(source, timestamp: timestamp, duration: duration), relativeTo: liveURL)?.absoluteURL
        case .flussonic:
            let base = liveURL.deletingLastPathComponent()
            return base.appendingPathComponent("archive-\(timestamp)-\(duration).m3u8")
        case .xtream:
            guard let source else { return nil }
            return URL(string: render(source, timestamp: timestamp, duration: duration), relativeTo: liveURL)?.absoluteURL
        }
    }

    private func render(_ template: String, timestamp: Int, duration: Int) -> String {
        template
            .replacingOccurrences(of: "{utc}", with: "\(timestamp)")
            .replacingOccurrences(of: "{duration}", with: "\(duration)")
    }
}

public typealias M3U = Playlist

extension Dictionary where Key == String, Value == String {
    func normalizedValue(for key: String) -> String? {
        let normalizedKey = key.normalizedAttributeKey
        return first { $0.key.normalizedAttributeKey == normalizedKey }?.value
    }

    func normalizedURL(for key: String) -> URL? {
        normalizedValue(for: key).flatMap(URL.init(string:))
    }
}

extension String {
    var normalizedAttributeKey: String {
        lowercased().replacingOccurrences(of: "_", with: "-")
    }
}
