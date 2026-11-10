import Foundation

extension SeriesInfo {
    /// Reads an episode's show, season and number from its title, or returns nil when the title doesn't mark one.
    ///
    /// The marker is `S01E02`, `S01 E02`, `S01.E02`, `1x02` or `Season 1 Episode 2`. What comes before it is the
    /// show's name, less a year in brackets (`Show (2019)`) or an air date (`Show 05 05 2025`). What comes after it
    /// is the episode's own name, or an air date.
    public init?(title: String) {
        guard let info = SeriesTitleParser.parse(title) else { return nil }
        self = info
    }
}

enum SeriesTitleParser {
    // Compiled once: an Xtream export can list hundreds of thousands of entries.
    private static let markers: [NSRegularExpression] = [
        #"(?<![A-Za-z0-9])S(\d{1,4})[\s._-]{0,3}E(\d{1,4})(?!\d)"#,
        #"(?<![A-Za-z0-9])(\d{1,2})x(\d{1,3})(?!\d)"#,
        #"(?<![A-Za-z0-9])season[\s._-]*(\d{1,3})[\s._,-]*(?:episode|ep\.?)[\s._-]*(\d{1,4})(?!\d)"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    private static let bracketedYear = try! NSRegularExpression(pattern: #"\s*[\(\[]((?:19|20)\d{2})[\)\]]"#)
    private static let trailingAirDate = try! NSRegularExpression(
        pattern: #"[\s._-]+(\d{1,2}[\s./-]\d{1,2}[\s./-]\d{2,4}|\d{4}[./-]\d{2}[./-]\d{2})\s*$"#
    )
    private static let wholeAirDate = try! NSRegularExpression(
        pattern: #"^(\d{1,2}[\s./-]\d{1,2}[\s./-]\d{2,4}|\d{4}[./-]\d{2}[./-]\d{2})$"#
    )

    private static let separators = CharacterSet(charactersIn: "-–—:|._,").union(.whitespacesAndNewlines)

    static func parse(_ title: String) -> SeriesInfo? {
        // Every marker has a number in it, and most titles don't.
        guard title.contains(where: \.isNumber) else { return nil }

        let nsTitle = title as NSString
        let fullRange = NSRange(location: 0, length: nsTitle.length)

        for marker in markers {
            guard let match = marker.firstMatch(in: title, range: fullRange), match.numberOfRanges >= 3 else { continue }

            let season = Int(nsTitle.substring(with: match.range(at: 1)))
            let episode = Int(nsTitle.substring(with: match.range(at: 2)))
            let before = nsTitle.substring(to: match.range.location)
            let after = nsTitle.substring(from: match.range.location + match.range.length)

            return build(title: title, before: before, after: after, season: season, episode: episode)
        }

        return nil
    }

    private static func build(title: String, before: String, after: String, season: Int?, episode: Int?) -> SeriesInfo {
        var name = before
        var year: Int?
        var airDate: String?

        if let match = firstMatch(bracketedYear, in: name) {
            year = Int((name as NSString).substring(with: match.range(at: 1)))
            name = (name as NSString).replacingCharacters(in: match.range, with: "")
        }

        if let match = firstMatch(trailingAirDate, in: name) {
            airDate = (name as NSString).substring(with: match.range(at: 1))
            name = (name as NSString).replacingCharacters(in: match.range, with: "")
        }

        // Release-style names ("The.Show.Name") use dots and underscores for spaces; others use them for real.
        if name.contains(where: \.isWhitespace) == false {
            name = name.replacingOccurrences(of: "[._]+", with: " ", options: .regularExpression)
        }

        name = clean(name)

        var episodeTitle: String? = clean(after)
        if let candidate = episodeTitle, candidate.isEmpty {
            episodeTitle = nil
        } else if let candidate = episodeTitle, firstMatch(wholeAirDate, in: candidate) != nil {
            airDate = airDate ?? candidate
            episodeTitle = nil
        }

        // A title that is only a marker has no show to name; the rest of it is the best name there is.
        if name.isEmpty {
            name = episodeTitle ?? clean(title)
            episodeTitle = nil
        }

        return SeriesInfo(
            name: name,
            season: season,
            episode: episode,
            episodeTitle: episodeTitle,
            year: year,
            airDate: airDate
        )
    }

    private static func firstMatch(_ expression: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        expression.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
    }

    private static func clean(_ string: String) -> String {
        string
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: separators)
    }
}
