import Foundation

/// A programme from `get_short_epg`, `get_simple_data_table` or `get_epg`.
public struct XtreamEPGListing: Decodable, Hashable, Sendable {
    public var id: String
    /// The XMLTV channel ID.
    public var channelID: String?
    /// Decoded from base64.
    public var title: String
    /// Decoded from base64.
    public var summary: String?
    public var language: String?
    /// Unix seconds. The panel's `start` is a string in its own time zone, so only the timestamp is read.
    public var start: Int?
    public var end: Int?
    /// `get_simple_data_table` only.
    public var isNowPlaying: Bool?
    /// `get_simple_data_table` only: the programme can be replayed.
    public var hasArchive: Bool?

    public var startDate: Date? { start.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    public var endDate: Date? { end.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    enum CodingKeys: String, CodingKey {
        case id, title, description, start, end, stop
        case channelID = "channel_id"
        case language = "lang"
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
        case isNowPlaying = "now_playing"
        case hasArchive = "has_archive"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenientString(.id) ?? UUID().uuidString
        channelID = container.lenientString(.channelID)
        title = container.lenientString(.title).map(XtreamValue.decodeBase64Text) ?? ""
        summary = container.lenientString(.description).map(XtreamValue.decodeBase64Text)
        language = container.lenientString(.language)
        // `end` is a string on some panels and a number on others, even within one panel.
        start = container.lenientInt(.startTimestamp) ?? XtreamValue.unixTime(container.lenientString(.start))
        end = container.lenientInt(.stopTimestamp)
            ?? XtreamValue.unixTime(container.firstString(.end, .stop))
        isNowPlaying = container.lenientBool(.isNowPlaying)
        hasArchive = container.lenientBool(.hasArchive)
    }
}

struct XtreamEPGResponse: Decodable {
    let listings: XtreamList<XtreamEPGListing>

    private enum CodingKeys: String, CodingKey {
        case listings = "epg_listings"
    }

    init(from decoder: any Decoder) throws {
        // `get_epg` answers a bare array; the other two wrap it.
        if let bare = try? [Lossy<XtreamEPGListing>](from: decoder) {
            let items = bare.compactMap(\.value)
            listings = XtreamList(items: items, droppedCount: bare.count - items.count)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lossy = (try? container.decodeIfPresent([Lossy<XtreamEPGListing>].self, forKey: .listings)) ?? []
        let items = lossy.compactMap(\.value)
        listings = XtreamList(items: items, droppedCount: lossy.count - items.count)
    }
}
