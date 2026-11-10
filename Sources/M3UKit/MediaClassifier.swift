import Foundation

/// Decides whether a playlist entry is a live channel, a movie, an episode or radio.
///
/// The link is the strongest evidence, because an IPTV panel writes it, while group names are whatever the
/// provider typed. A channel in a group called "Sky Cinema" is still live when its link says so. In order:
///
/// 1. An explicit `tvg-type`.
/// 2. The shape of the link: a panel's `/live/`, `/movie/` and `/series/` paths, its short live form
///    (`/user/pass/123`), and XUI's `/play/{token}` links.
/// 3. The container extension: a video file is on demand, an audio file is radio.
/// 4. For on-demand entries, an episode marker in the title, or a series word in the group, makes it an episode.
///    Anything else is a movie.
/// 5. For a link that says nothing (an HLS playlist, a bare stream), an episode marker in the title, then words in
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
        classify(
            title: title,
            url: url,
            attributes: attributes,
            group: group,
            isVODPlaylist: isVODPlaylist,
            series: SeriesInfo(title: title)
        )
    }

    /// For a caller that has already read the title's episode marker.
    static func classify(
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

        let isEpisode = series != nil || words?.containsAny(of: seriesWords) == true
        switch linkKind(parts) {
        case .live: return .live
        case .radio: return .radio
        case .movie: return .movie
        case .series: return .series
        case .onDemand: return isEpisode ? .series : .movie
        case nil: break
        }

        switch containerKind(of: url, parts) {
        case .video: return isEpisode ? .series : .movie
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
