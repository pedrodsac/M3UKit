import Foundation

public struct XtreamCategory: Decodable, Hashable, Sendable {
    /// A string on the wire, and the key streams join on.
    public var categoryID: String
    public var name: String
    /// 0 for a top-level category.
    public var parentID: Int

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case name = "category_name"
        case parentID = "parent_id"
    }

    public init(categoryID: String, name: String, parentID: Int = 0) {
        self.categoryID = categoryID
        self.name = name
        self.parentID = parentID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryID = try requiredKey(container.lenientString(.categoryID), CodingKeys.categoryID, in: container)
        name = container.lenientString(.name) ?? categoryID
        parentID = container.lenientInt(.parentID) ?? 0
    }
}

/// An entry of `get_live_streams`, which lists live channels and radio stations.
public struct XtreamLiveStream: Decodable, Hashable, Sendable {
    /// The channel's number in the panel's own order.
    public var num: Int?
    public var name: String
    /// `live`, `created_live` (a channel the panel builds from files, such as a 24/7 loop) or `radio_streams`.
    public var streamType: String?
    public var streamID: Int
    public var iconURL: String?
    /// The XMLTV channel ID, which the guide matches on.
    public var epgChannelID: String?
    /// Unix seconds.
    public var added: Int?
    public var isAdult: Bool
    public var categoryID: String?
    public var categoryIDs: [Int]
    public var customSID: String?
    /// `tv_archive`: the panel keeps a catch-up archive of this channel.
    public var hasArchive: Bool
    /// `tv_archive_duration`: days of archive.
    public var archiveDays: Int?
    public var directSource: String?
    public var thumbnailURL: String?

    enum CodingKeys: String, CodingKey {
        case num, name, added, thumbnail
        case streamType = "stream_type"
        case streamID = "stream_id"
        case iconURL = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case isAdult = "is_adult"
        case categoryID = "category_id"
        case categoryIDs = "category_ids"
        case customSID = "custom_sid"
        case hasArchive = "tv_archive"
        case archiveDays = "tv_archive_duration"
        case directSource = "direct_source"
        case thumbnailURL
    }

    public var isRadio: Bool { streamType == "radio_streams" }
    public var isCreatedLive: Bool { streamType == "created_live" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamID = try requiredKey(container.lenientInt(.streamID), CodingKeys.streamID, in: container)
        num = container.lenientInt(.num)
        name = container.lenientString(.name) ?? ""
        streamType = container.lenientString(.streamType)
        iconURL = container.lenientString(.iconURL)
        epgChannelID = container.lenientString(.epgChannelID)
        added = container.lenientInt(.added)
        isAdult = container.lenientBool(.isAdult) ?? false
        categoryID = container.lenientString(.categoryID)
        categoryIDs = container.lenientInts(.categoryIDs)
        customSID = container.lenientString(.customSID)
        hasArchive = container.lenientBool(.hasArchive) ?? false
        archiveDays = container.lenientInt(.archiveDays)
        directSource = container.lenientString(.directSource)
        // The wire key is `thumbnail`; the property is named for what it holds.
        thumbnailURL = container.lenientString(.thumbnail) ?? container.lenientString(.thumbnailURL)
    }
}

/// An entry of `get_vod_streams`. XUI also sends the details a detail page shows, so they're read when present.
public struct XtreamVODStream: Decodable, Hashable, Sendable {
    public var num: Int?
    public var name: String
    /// The name without a year suffix. XUI only.
    public var title: String?
    public var year: Int?
    public var streamID: Int
    public var iconURL: String?
    /// 0 to 10.
    public var rating: Double?
    /// 0 to 5.
    public var rating5: Double?
    public var added: Int?
    public var isAdult: Bool
    public var categoryID: String?
    public var categoryIDs: [Int]
    public var containerExtension: String?
    public var customSID: String?
    public var directSource: String?

    public var plot: String?
    public var cast: String?
    public var director: String?
    public var genre: String?
    public var releaseDate: String?
    public var youtubeTrailer: String?
    public var episodeRunTime: Int?
    public var tmdbID: String?

    enum CodingKeys: String, CodingKey {
        case num, name, title, year, rating, added, plot, cast, director, genre, tmdb, trailer
        case streamID = "stream_id"
        case iconURL = "stream_icon"
        case rating5 = "rating_5based"
        case isAdult = "is_adult"
        case categoryID = "category_id"
        case categoryIDs = "category_ids"
        case containerExtension = "container_extension"
        case customSID = "custom_sid"
        case directSource = "direct_source"
        case releaseDate = "release_date"
        case youtubeTrailer = "youtube_trailer"
        case episodeRunTime = "episode_run_time"
        case tmdbID = "tmdb_id"
    }

    /// The rating on a 0 to 10 scale, from whichever of the two the panel sent. Nil for no rating, which panels
    /// write as 0.
    public var rating10: Double? {
        if let rating, rating > 0 { return rating }
        if let rating5, rating5 > 0 { return rating5 * 2 }
        return nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamID = try requiredKey(container.lenientInt(.streamID), CodingKeys.streamID, in: container)
        num = container.lenientInt(.num)
        name = container.lenientString(.name) ?? container.lenientString(.title) ?? ""
        title = container.lenientString(.title)
        year = container.lenientYear(.year)
        iconURL = container.lenientString(.iconURL)
        rating = container.lenientDouble(.rating)
        rating5 = container.lenientDouble(.rating5)
        added = container.lenientInt(.added)
        isAdult = container.lenientBool(.isAdult) ?? false
        categoryID = container.lenientString(.categoryID)
        categoryIDs = container.lenientInts(.categoryIDs)
        containerExtension = container.lenientString(.containerExtension)?.lowercased()
        customSID = container.lenientString(.customSID)
        directSource = container.lenientString(.directSource)
        plot = container.lenientString(.plot)
        cast = container.lenientString(.cast)
        director = container.lenientString(.director)
        genre = container.lenientString(.genre)
        releaseDate = container.lenientString(.releaseDate)
        youtubeTrailer = container.firstString(.youtubeTrailer, .trailer)
        episodeRunTime = container.lenientInt(.episodeRunTime)
        tmdbID = container.firstString(.tmdbID, .tmdb)
    }
}

/// An entry of `get_series`: one row per show, not per episode. `info` of `get_series_info` has the same fields,
/// less the IDs, so one type reads both.
public struct XtreamSeries: Decodable, Hashable, Sendable {
    public var num: Int?
    public var name: String
    public var title: String?
    public var year: Int?
    /// Nil in the `info` of `get_series_info`.
    public var seriesID: Int?
    public var coverURL: String?
    public var plot: String?
    public var cast: String?
    public var director: String?
    public var genre: String?
    public var releaseDate: String?
    /// Unix seconds: when the show last changed, which is when an episode was added.
    public var lastModified: Int?
    public var rating: Double?
    public var rating5: Double?
    public var backdropURLs: [String]
    public var youtubeTrailer: String?
    public var episodeRunTime: Int?
    public var categoryID: String?
    public var categoryIDs: [Int]
    public var tmdbID: String?
    public var isAdult: Bool

    enum CodingKeys: String, CodingKey {
        case num, name, title, year, cover, plot, cast, director, genre, rating, tmdb
        case seriesID = "series_id"
        case coverURL
        case releaseDate = "release_date"
        case releaseDateCamel = "releaseDate"
        case lastModified = "last_modified"
        case rating5 = "rating_5based"
        case backdropURLs = "backdrop_path"
        case youtubeTrailer = "youtube_trailer"
        case episodeRunTime = "episode_run_time"
        case categoryID = "category_id"
        case categoryIDs = "category_ids"
        case tmdbID = "tmdb_id"
        case isAdult = "is_adult"
    }

    public var rating10: Double? {
        if let rating, rating > 0 { return rating }
        if let rating5, rating5 > 0 { return rating5 * 2 }
        return nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        num = container.lenientInt(.num)
        seriesID = container.lenientInt(.seriesID)
        title = container.lenientString(.title)
        name = container.lenientString(.name) ?? title ?? ""
        year = container.lenientYear(.year)
        coverURL = container.lenientString(.cover) ?? container.lenientString(.coverURL)
        plot = container.lenientString(.plot)
        cast = container.lenientString(.cast)
        director = container.lenientString(.director)
        genre = container.lenientString(.genre)
        releaseDate = container.firstString(.releaseDate, .releaseDateCamel)
        lastModified = container.lenientInt(.lastModified)
        rating = container.lenientDouble(.rating)
        rating5 = container.lenientDouble(.rating5)
        backdropURLs = container.lenientStrings(.backdropURLs)
        youtubeTrailer = container.lenientString(.youtubeTrailer)
        episodeRunTime = container.lenientInt(.episodeRunTime)
        categoryID = container.lenientString(.categoryID)
        categoryIDs = container.lenientInts(.categoryIDs)
        tmdbID = container.firstString(.tmdbID, .tmdb)
        isAdult = container.lenientBool(.isAdult) ?? false
    }
}
