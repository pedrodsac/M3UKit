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

    public init(
        title: String,
        url: URL,
        duration: Double? = nil,
        attributes: [String: String] = [:],
        contentType: MediaContentType = .other,
        series: SeriesInfo? = nil,
        group: String? = nil,
        hls: MediaHLSMetadata = MediaHLSMetadata()
    ) {
        self.title = title
        self.url = url
        self.duration = duration
        self.attributes = attributes
        self.contentType = contentType
        self.series = series
        self.group = group
        self.hls = hls
    }

    public var tvgID: String? { attributes.normalizedValue(for: "tvg-id") }
    public var tvgName: String? { attributes.normalizedValue(for: "tvg-name") }
    public var tvgLogo: URL? { attributes.normalizedURL(for: "tvg-logo") }
    public var tvgCountry: String? { attributes.normalizedValue(for: "tvg-country") }
    public var tvgLanguage: String? { attributes.normalizedValue(for: "tvg-language") }
    public var tvgType: String? { attributes.normalizedValue(for: "tvg-type") }
    public var tvgEPGID: String? { attributes.normalizedValue(for: "tvg-epgid") }
    public var tvgShift: String? { attributes.normalizedValue(for: "tvg-shift") }
    public var groupTitle: String? { group ?? attributes.normalizedValue(for: "group-title") ?? attributes.normalizedValue(for: "group_id") }
    public var audioTracks: [String] {
        attributes.normalizedValue(for: "audio-track")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
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

public enum HLSPlaylistType: String, Codable, Hashable, Sendable {
    case event = "EVENT"
    case vod = "VOD"
}

public struct SeriesInfo: Codable, Hashable, Sendable {
    public var name: String
    public var season: Int?
    public var episode: Int?

    public init(name: String, season: Int? = nil, episode: Int? = nil) {
        self.name = name
        self.season = season
        self.episode = episode
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
