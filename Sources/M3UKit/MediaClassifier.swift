import Foundation

/// Decides whether a playlist entry is a live channel, a movie, an episode or radio.
///
/// The link is the strongest evidence, because an IPTV panel writes it, while group names are whatever the
/// provider typed. A channel in a group called "Sky Cinema" is still live when its link says so. In order:
///
/// 1. An explicit `tvg-type`.
/// 2. `media="true"`, which marks an entry as on demand rather than a channel. The link can still say movie or
///    episode; otherwise an episode marker, a dated title or a series word makes an episode, a video file, a year in
///    brackets or a movie word in the group makes a movie, and anything else is `other`.
/// 3. The shape of the link: a panel's `/live/`, `/movie/` and `/series/` paths, its short live form
///    (`/user/pass/123`), and XUI's `/play/{token}` links.
/// 4. The container extension: a video file is on demand, an audio file is radio.
/// 5. For on-demand entries, an episode marker in the title, a title that ends in an air date
///    (`Show - 5/11/2026`), or a series word in the group, makes it an episode. Anything else is a movie.
/// 6. For a link that says nothing (an HLS playlist, a bare stream), an episode marker in the title, then words in
///    the group, then an `audio-track` attribute. Otherwise it is live.
///
/// Group words match whole words only, so "Vodafone" is not "vod" and "Filmbox" is not "film".
public enum MediaClassifier {
    public static func classify(
        title: String,
        url: URL,
        attributes: [String: String],
        group: String?,
        isVODPlaylist: Bool = false
    ) -> MediaContentType {
        classification(title: title, url: url, attributes: attributes, group: group, isVODPlaylist: isVODPlaylist)
            .contentType
    }

    /// The entry's kind together with the show and episode its title names. A title that ends in an air date names
    /// an episode only once the entry is known to be on demand, so ask for both here rather than reading the title
    /// with `SeriesInfo(title:)` on the side.
    public static func classification(
        title: String,
        url: URL,
        attributes: [String: String],
        group: String?,
        isVODPlaylist: Bool = false
    ) -> MediaClassification {
        let series = SeriesInfo(title: title)
        let contentType = contentType(
            title: title,
            url: url,
            attributes: attributes,
            group: group,
            isVODPlaylist: isVODPlaylist,
            series: series
        )
        guard contentType == .series, series == nil else {
            return MediaClassification(contentType: contentType, series: series)
        }

        return MediaClassification(contentType: contentType, series: SeriesTitleParser.parseDated(title))
    }

    private static func contentType(
        title: String,
        url: URL,
        attributes: [String: String],
        group: String?,
        isVODPlaylist: Bool,
        series: SeriesInfo?
    ) -> MediaContentType {
        if let explicit = attributes.normalizedValue(for: "tvg-type").flatMap(explicitType) {
            return explicit
        }

        let words = group.map(GroupWords.init)
        let parts = URLParts(url)
        let link = linkKind(parts)

        func onDemand(otherwise fallback: MediaContentType) -> MediaContentType {
            let isEpisode = series != nil
                || words?.containsAny(of: seriesWords) == true
                || SeriesTitleParser.parseDated(title) != nil
            return isEpisode ? .series : fallback
        }

        // Kodi's IPTV Simple client marks a catch-up programme or a recording this way, next to `radio="true"`.
        if attributes.normalizedValue(for: "media")?.lowercased() == "true" {
            switch link {
            case .movie: return .movie
            case .series: return .series
            default: break
            }

            let isMovie = link == .onDemand
                || containerKind(of: url, parts) == .video
                || hasBracketedYear(title)
                || words?.containsAny(of: onDemandWords) == true
            return onDemand(otherwise: isMovie ? .movie : .other)
        }

        switch link {
        case .live: return .live
        case .radio: return .radio
        case .movie: return .movie
        case .series: return .series
        case .onDemand: return onDemand(otherwise: .movie)
        case nil: break
        }

        switch containerKind(of: url, parts) {
        case .video: return onDemand(otherwise: .movie)
        case .audio: return .radio
        case nil: break
        }

        if series != nil { return .series }
        if isVODPlaylist { return .movie }

        if hasBracketedYear(title), words?.containsAny(of: onDemandWords) == true { return .movie }

        if attributes.normalizedValue(for: "audio-track") != nil
            || attributes.normalizedValue(for: "radio")?.lowercased() == "true"
            || words?.containsAny(of: radioWords) == true {
            return .radio
        }

        return .live
    }

    // MARK: - Explicit type

    private static func explicitType(_ value: String) -> MediaContentType? {
        switch value.lowercased() {
        case "live", "channel", "tv": .live
        case "movie", "vod", "film": .movie
        case "series", "episode": .series
        case "radio", "audio": .radio
        case "show": .show
        default: nil
        }
    }

    // MARK: - The link

    private enum LinkKind {
        case live, radio, movie, series
        /// On demand, but a movie or an episode isn't settled by the link.
        case onDemand
    }

    private static func linkKind(_ parts: URLParts) -> LinkKind? {
        let segments = parts.pathSegments

        // Panel paths and the CDN-style `/vod/` and `/radio/` folders. The last segment is a file, never a folder.
        for segment in segments.dropLast() {
            switch segment {
            case "movie": return .movie
            case "series": return .series
            case "vod": return .onDemand
            case "radio": return .radio
            case "live", "timeshift": return .live
            default: continue
            }
        }

        // XUI: `/play/{token}/ts` is a live stream; `/play/{token}#.mp4` is a file, named by the fragment.
        if let playIndex = segments.lastIndex(of: "play") {
            let following = segments[(playIndex + 1)...]
            if following.count == 2, let last = following.last, last == "ts" || last == "m3u8" { return .live }
            if following.count == 1, let fragment = parts.fragment,
               containerKind(forExtension: fragment.trimmingPrefix(".")) == .video {
                return .onDemand
            }
        }

        // Classic `get.php` writes live links as `/{user}/{pass}/{id}`.
        if XtreamStreamURL(parts: parts)?.kind == .live { return .live }

        return nil
    }

    // MARK: - Container extension

    private enum ContainerKind { case video, audio }

    private static let videoExtensions: Set<String> = [
        "mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "ogv", "divx",
    ]
    private static let audioExtensions: Set<String> = ["mp3", "aac", "m4a", "ogg", "opus", "flac", "wav", "wma"]

    private static func containerKind(of url: URL, _ parts: URLParts) -> ContainerKind? {
        if let last = parts.pathSegments.last, let dot = last.lastIndex(of: "."),
           let kind = containerKind(forExtension: last[last.index(after: dot)...].lowercased()) {
            return kind
        }

        return parts.fragment.flatMap { containerKind(forExtension: $0.trimmingPrefix(".").lowercased()) }
    }

    private static func containerKind(forExtension value: some StringProtocol) -> ContainerKind? {
        let value = value.lowercased()
        if videoExtensions.contains(value) { return .video }
        if audioExtensions.contains(value) { return .audio }
        return nil
    }

    // MARK: - Group words

    private static let seriesWords: Set<String> = [
        "series", "serie", "shows", "episodes", "temporada", "temporadas", "saison", "staffel",
    ]
    private static let onDemandWords: Set<String> = [
        "movie", "movies", "film", "films", "filme", "filmes", "vod", "cinema", "pelicula", "peliculas",
    ]
    private static let radioWords: Set<String> = ["radio", "radios"]

    private struct GroupWords {
        let words: Set<String>

        init(_ group: String) {
            words = Set(group.lowercased().split { $0.isLetter == false && $0.isNumber == false }.map(String.init))
        }

        func containsAny(of candidates: Set<String>) -> Bool {
            words.isDisjoint(with: candidates) == false
        }
    }

    // MARK: - Title

    private static let bracketedYear = try! NSRegularExpression(pattern: #"[\(\[](?:19|20)\d{2}[\)\]]"#)

    private static func hasBracketedYear(_ title: String) -> Bool {
        bracketedYear.firstMatch(in: title, range: NSRange(location: 0, length: (title as NSString).length)) != nil
    }
}

private extension StringProtocol {
    func trimmingPrefix(_ prefix: Character) -> SubSequence {
        first == prefix ? dropFirst() : self[...]
    }
}
