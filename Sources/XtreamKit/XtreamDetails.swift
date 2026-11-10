import Foundation

/// A video or audio stream from the ffprobe output the panel stores for a file. Both kinds read into one type:
/// the fields that don't apply stay nil.
public struct XtreamMediaStream: Decodable, Hashable, Sendable {
    public var codecName: String?
    public var profile: String?
    public var width: Int?
    public var height: Int?
    public var displayAspectRatio: String?
    /// `r_frame_rate`, such as `24000/1001`.
    public var frameRate: String?
    public var pixelFormat: String?
    /// `smpte2084` is HDR10 and `arib-std-b67` is HLG.
    public var colorTransfer: String?
    public var colorPrimaries: String?
    /// `dvh1` or `dvhe` is Dolby Vision.
    public var codecTag: String?
    public var channels: Int?
    public var channelLayout: String?
    public var sampleRate: Int?
    public var bitRate: Int?
    public var language: String?

    enum CodingKeys: String, CodingKey {
        case profile, width, height, channels, tags
        case codecName = "codec_name"
        case displayAspectRatio = "display_aspect_ratio"
        case frameRate = "r_frame_rate"
        case pixelFormat = "pix_fmt"
        case colorTransfer = "color_transfer"
        case colorPrimaries = "color_primaries"
        case codecTag = "codec_tag_string"
        case channelLayout = "channel_layout"
        case sampleRate = "sample_rate"
        case bitRate = "bit_rate"
        case language
    }

    private enum TagKeys: String, CodingKey {
        case language
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codecName = container.lenientString(.codecName)
        profile = container.lenientString(.profile)
        width = container.lenientInt(.width)
        height = container.lenientInt(.height)
        displayAspectRatio = container.lenientString(.displayAspectRatio)
        frameRate = container.lenientString(.frameRate)
        pixelFormat = container.lenientString(.pixelFormat)
        colorTransfer = container.lenientString(.colorTransfer)
        colorPrimaries = container.lenientString(.colorPrimaries)
        codecTag = container.lenientString(.codecTag)
        channels = container.lenientInt(.channels)
        channelLayout = container.lenientString(.channelLayout)
        sampleRate = container.lenientInt(.sampleRate)
        bitRate = container.lenientInt(.bitRate)
        language = (try? container.nestedContainer(keyedBy: TagKeys.self, forKey: .tags))?.lenientString(.language)
            ?? container.lenientString(.language)
    }

    public var isHDR: Bool {
        colorTransfer == "smpte2084" || colorTransfer == "arib-std-b67"
    }

    public var isDolbyVision: Bool {
        codecTag == "dvh1" || codecTag == "dvhe"
    }

    /// `4K`, `HD` or `SD` from the picture's width and height.
    public var resolutionLabel: String? {
        guard let width, let height else { return nil }
        if width >= 3200 || height >= 2000 { return "4K" }
        if width >= 1200 || height >= 700 { return "HD" }
        return "SD"
    }
}

/// `info` of `get_vod_info`.
public struct XtreamMovieInfo: Decodable, Hashable, Sendable {
    public var kinopoiskURL: String?
    public var tmdbID: String?
    public var name: String?
    public var originalName: String?
    public var coverBigURL: String?
    public var movieImageURL: String?
    public var backdropURLs: [String]
    public var releaseDate: String?
    public var episodeRunTime: Int?
    public var durationSeconds: Int?
    /// `HH:MM:SS`.
    public var duration: String?
    public var youtubeTrailer: String?
    public var director: String?
    public var cast: String?
    public var plot: String?
    /// An age, such as `16+`.
    public var age: String?
    /// A rating, such as `PG-13`.
    public var mpaaRating: String?
    public var rating: Double?
    public var ratingCountKinopoisk: Int?
    public var country: String?
    public var genre: String?
    public var bitrate: Int?
    public var video: XtreamMediaStream?
    public var audio: XtreamMediaStream?
    public var subtitles: [String]

    enum CodingKeys: String, CodingKey {
        case name, duration, director, cast, plot, age, rating, country, genre, bitrate, video, audio, subtitles
        case actors, description, releasedate, runtime
        case kinopoiskURL = "kinopoisk_url"
        case tmdbID = "tmdb_id"
        case originalName = "o_name"
        case coverBigURL = "cover_big"
        case movieImageURL = "movie_image"
        case backdropURLs = "backdrop_path"
        case releaseDate = "release_date"
        case episodeRunTime = "episode_run_time"
        case durationSeconds = "duration_secs"
        case youtubeTrailer = "youtube_trailer"
        case mpaaRating = "mpaa_rating"
        case ratingCountKinopoisk = "rating_count_kinopoisk"
    }

    public var runtimeMinutes: Int? {
        if let durationSeconds, durationSeconds > 0 { return Int((Double(durationSeconds) / 60).rounded()) }
        if let episodeRunTime, episodeRunTime > 0 { return episodeRunTime }
        return duration.flatMap(XtreamMovieInfo.minutes(fromClock:))
    }

    static func minutes(fromClock clock: String) -> Int? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let total = parts[0] * 60 + parts[1] + (parts[2] >= 30 ? 1 : 0)
        return total > 0 ? total : nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kinopoiskURL = container.lenientString(.kinopoiskURL)
        tmdbID = container.lenientString(.tmdbID)
        name = container.lenientString(.name)
        originalName = container.lenientString(.originalName)
        coverBigURL = container.lenientString(.coverBigURL)
        movieImageURL = container.lenientString(.movieImageURL)
        backdropURLs = container.lenientStrings(.backdropURLs)
        releaseDate = container.firstString(.releaseDate, .releasedate)
        episodeRunTime = container.lenientInt(.episodeRunTime) ?? container.lenientInt(.runtime)
        durationSeconds = container.lenientInt(.durationSeconds)
        duration = container.lenientString(.duration)
        youtubeTrailer = container.lenientString(.youtubeTrailer)
        director = container.lenientString(.director)
        cast = container.firstString(.cast, .actors)
        plot = container.firstString(.plot, .description)
        age = container.lenientString(.age)
        mpaaRating = container.lenientString(.mpaaRating)
        rating = container.lenientDouble(.rating)
        ratingCountKinopoisk = container.lenientInt(.ratingCountKinopoisk)
        country = container.lenientString(.country)
        genre = container.lenientString(.genre)
        bitrate = container.lenientInt(.bitrate)
        // PHP writes `[]` for a missing object, which doesn't decode as one.
        video = try? container.decodeIfPresent(XtreamMediaStream.self, forKey: .video)
        audio = try? container.decodeIfPresent(XtreamMediaStream.self, forKey: .audio)
        subtitles = Self.subtitleLabels(container)
    }

    private static func subtitleLabels(_ container: KeyedDecodingContainer<CodingKeys>) -> [String] {
        if let labels = try? container.decodeIfPresent([String].self, forKey: .subtitles) {
            return labels.compactMap(XtreamValue.normalized)
        }
        return ((try? container.decodeIfPresent([Lossy<XtreamMediaStream>].self, forKey: .subtitles)) ?? [])
            .compactMap { $0.value?.language }
    }
}

/// `movie_data` of `get_vod_info`: the list item again, to repair one with missing fields.
public struct XtreamMovieData: Decodable, Hashable, Sendable {
    public var streamID: Int
    public var name: String
    public var title: String?
    public var year: Int?
    public var added: Int?
    public var categoryID: String?
    public var categoryIDs: [Int]
    public var containerExtension: String?
    public var customSID: String?
    public var directSource: String?

    enum CodingKeys: String, CodingKey {
        case name, title, year, added
        case streamID = "stream_id"
        case categoryID = "category_id"
        case categoryIDs = "category_ids"
        case containerExtension = "container_extension"
        case customSID = "custom_sid"
        case directSource = "direct_source"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamID = try requiredKey(container.lenientInt(.streamID), CodingKeys.streamID, in: container)
        name = container.lenientString(.name) ?? container.lenientString(.title) ?? ""
        title = container.lenientString(.title)
        year = container.lenientYear(.year)
        added = container.lenientInt(.added)
        categoryID = container.lenientString(.categoryID)
        categoryIDs = container.lenientInts(.categoryIDs)
        containerExtension = container.lenientString(.containerExtension)?.lowercased()
        customSID = container.lenientString(.customSID)
        directSource = container.lenientString(.directSource)
    }
}

/// `get_vod_info`. Both parts are nil for a movie the panel no longer has, which it answers with `{"info":[]}`.
public struct XtreamVODInfo: Decodable, Hashable, Sendable {
    public var info: XtreamMovieInfo?
    public var movieData: XtreamMovieData?

    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        info = try? container.decodeIfPresent(XtreamMovieInfo.self, forKey: .info)
        movieData = try? container.decodeIfPresent(XtreamMovieData.self, forKey: .movieData)
    }

    public var isMissing: Bool { info == nil && movieData == nil }
}

public struct XtreamSeason: Decodable, Hashable, Sendable {
    public var id: Int?
    /// `Season 1`, or a real name such as `Specials`.
    public var name: String?
    /// 0 is the specials.
    public var seasonNumber: Int
    public var episodeCount: Int?
    public var overview: String?
    public var airDate: String?
    public var coverURL: String?
    public var coverBigURL: String?
    public var voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, cover
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case airDate = "air_date"
        case coverURL
        case coverBigURL = "cover_big"
        case voteAverage = "vote_average"
    }

    init(seasonNumber: Int) {
        self.seasonNumber = seasonNumber
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasonNumber = try requiredKey(container.lenientInt(.seasonNumber), CodingKeys.seasonNumber, in: container)
        id = container.lenientInt(.id)
        name = container.lenientString(.name)
        episodeCount = container.lenientInt(.episodeCount)
        overview = container.lenientString(.overview)
        airDate = container.lenientString(.airDate)
        coverURL = container.lenientString(.cover) ?? container.lenientString(.coverURL)
        coverBigURL = container.lenientString(.coverBigURL)
        voteAverage = container.lenientDouble(.voteAverage)
    }
}

/// `info` of an episode in `get_series_info`.
public struct XtreamEpisodeInfo: Decodable, Hashable, Sendable {
    public var tmdbID: String?
    public var airDate: String?
    public var plot: String?
    public var durationSeconds: Int?
    public var duration: String?
    public var imageURL: String?
    public var rating: Double?
    public var season: Int?
    public var name: String?
    public var bitrate: Int?
    public var video: XtreamMediaStream?
    public var audio: XtreamMediaStream?
    public var crew: String?

    enum CodingKeys: String, CodingKey {
        case plot, duration, rating, season, name, bitrate, video, audio, crew
        case releasedate, air_date
        case tmdbID = "tmdb_id"
        case airDate = "release_date"
        case durationSeconds = "duration_secs"
        case imageURL = "movie_image"
        case coverBig = "cover_big"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tmdbID = container.lenientString(.tmdbID)
        airDate = container.firstString(.airDate, .releasedate, .air_date)
        plot = container.lenientString(.plot)
        durationSeconds = container.lenientInt(.durationSeconds)
        duration = container.lenientString(.duration)
        imageURL = container.firstString(.imageURL, .coverBig)
        rating = container.lenientDouble(.rating)
        season = container.lenientInt(.season)
        name = container.lenientString(.name)
        bitrate = container.lenientInt(.bitrate)
        video = try? container.decodeIfPresent(XtreamMediaStream.self, forKey: .video)
        audio = try? container.decodeIfPresent(XtreamMediaStream.self, forKey: .audio)
        crew = container.lenientString(.crew)
    }
}

public struct XtreamEpisode: Decodable, Hashable, Sendable {
    /// The ID in the episode's stream URL.
    public var id: Int
    public var episodeNumber: Int?
    public var title: String
    public var containerExtension: String?
    /// The season the episode is listed under.
    public var season: Int?
    public var added: Int?
    public var customSID: String?
    public var directSource: String?
    public var subtitles: [String]
    public var info: XtreamEpisodeInfo?

    enum CodingKeys: String, CodingKey {
        case id, title, season, added, subtitles, info
        case episodeNumber = "episode_num"
        case containerExtension = "container_extension"
        case customSID = "custom_sid"
        case directSource = "direct_source"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try requiredKey(container.lenientInt(.id), CodingKeys.id, in: container)
        episodeNumber = container.lenientInt(.episodeNumber)
        title = container.lenientString(.title) ?? ""
        containerExtension = container.lenientString(.containerExtension)?.lowercased()
        season = container.lenientInt(.season)
        added = container.lenientInt(.added)
        customSID = container.lenientString(.customSID)
        directSource = container.lenientString(.directSource)
        subtitles = ((try? container.decodeIfPresent([String].self, forKey: .subtitles)) ?? [])
            .compactMap(XtreamValue.normalized)
        info = try? container.decodeIfPresent(XtreamEpisodeInfo.self, forKey: .info)
    }
}

/// `get_series_info`: a show's seasons and episodes. Episodes come as one list in season and episode order, each
/// carrying the season it was listed under.
public struct XtreamSeriesInfo: Decodable, Hashable, Sendable {
    public var info: XtreamSeries?
    public var seasons: [XtreamSeason]
    public var episodes: [XtreamEpisode]

    enum CodingKeys: String, CodingKey {
        case info, seasons, episodes
    }

    private struct SeasonKey: CodingKey {
        var stringValue: String
        var intValue: Int? { Int(stringValue) }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { stringValue = String(intValue) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `info` is `[]` for a show the panel doesn't have.
        info = try? container.decodeIfPresent(XtreamSeries.self, forKey: .info)

        var seasons = ((try? container.decodeIfPresent([Lossy<XtreamSeason>].self, forKey: .seasons)) ?? [])
            .compactMap(\.value)

        var episodes = Self.readEpisodes(container)
        episodes.sort {
            ($0.season ?? 0, $0.episodeNumber ?? Int.max, $0.id) < ($1.season ?? 0, $1.episodeNumber ?? Int.max, $1.id)
        }

        // `seasons` can be empty while the episodes are all there.
        if seasons.isEmpty {
            seasons = Set(episodes.compactMap(\.season)).sorted().map(XtreamSeason.init(seasonNumber:))
        }

        self.seasons = seasons
        self.episodes = episodes
    }

    /// `episodes` is an object keyed by season number, but some panels send an array of arrays instead.
    private static func readEpisodes(_ container: KeyedDecodingContainer<CodingKeys>) -> [XtreamEpisode] {
        var result: [XtreamEpisode] = []

        if let keyed = try? container.nestedContainer(keyedBy: SeasonKey.self, forKey: .episodes) {
            for key in keyed.allKeys {
                let list = (try? keyed.decode([Lossy<XtreamEpisode>].self, forKey: key)) ?? []
                for var episode in list.compactMap(\.value) {
                    // The key is what the panel files the episode under; the episode's own field can disagree.
                    episode.season = key.intValue ?? episode.season
                    result.append(episode)
                }
            }
        } else if var unkeyed = try? container.nestedUnkeyedContainer(forKey: .episodes) {
            var index = 0
            while unkeyed.isAtEnd == false {
                index += 1
                let list = (try? unkeyed.decode([Lossy<XtreamEpisode>].self)) ?? []
                for var episode in list.compactMap(\.value) {
                    episode.season = episode.season ?? index
                    result.append(episode)
                }
            }
        }

        return result
    }
}
