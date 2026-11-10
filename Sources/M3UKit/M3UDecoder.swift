import Foundation

public final class M3UDecoder: Sendable {
    public struct Options: Codable, Hashable, Sendable {
        public var skipsInvalidMedia: Bool
        public var trimsWhitespace: Bool

        public init(skipsInvalidMedia: Bool = true, trimsWhitespace: Bool = true) {
            self.skipsInvalidMedia = skipsInvalidMedia
            self.trimsWhitespace = trimsWhitespace
        }
    }

    public let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func decode(_ data: Data) throws -> Playlist {
        guard let string = String(data: data, encoding: .utf8) else {
            throw M3UDecodingError.invalidEncoding
        }

        return try decode(string)
    }

    public func decode(_ string: String) throws -> Playlist {
        var parser = M3UParser(options: options)
        return try parser.parse(string)
    }

    public func decode(contentsOf url: URL) throws -> Playlist {
        try decode(Data(contentsOf: url))
    }
}

public enum M3UDecodingError: Error, Equatable, LocalizedError, Sendable {
    case invalidEncoding
    case invalidMediaURL(String, line: Int)
    case missingMediaURL(title: String, line: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "The playlist data is not valid UTF-8."
        case let .invalidMediaURL(url, line):
            "Invalid media URL '\(url)' on line \(line)."
        case let .missingMediaURL(title, line):
            "Missing media URL for '\(title)' after line \(line)."
        }
    }
}

private struct PendingMedia {
    var title: String
    var duration: Double?
    var attributes: [String: String]
    var line: Int
}

private struct M3UParser {
    var options: M3UDecoder.Options

    private var playlist = Playlist()
    private var pendingMedia: PendingMedia?
    private var pendingGroup: String?
    private var currentKey: HLSKey?
    private var currentByteRange: ByteRange?
    private var currentMap: HLSMap?
    private var hasPendingDiscontinuity = false
    private var pendingTags: [PlaylistTag] = []
    private var pendingVLCOptions: [String: String] = [:]

    init(options: M3UDecoder.Options) {
        self.options = options
    }

    mutating func parse(_ text: String) throws -> Playlist {
        let lines = text.components(separatedBy: .newlines)

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = normalizedLine(rawLine)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTM3U") {
                playlist.isExtended = true
                playlist.attributes = AttributeParser.parse(line.removingPrefix("#EXTM3U"))
                continue
            }

            if line.hasPrefix("#EXTINF:") {
                pendingMedia = parseEXTINF(line, lineNumber: lineNumber)
                continue
            }

            if line.hasPrefix("#EXTGRP:") {
                pendingGroup = String(line.removingPrefix("#EXTGRP:"))
                continue
            }

            if line.hasPrefix("#") {
                parseTag(line)
                continue
            }

            if let pendingMedia {
                if let media = try buildMedia(from: pendingMedia, urlString: line, lineNumber: lineNumber) {
                    playlist.media.append(media)
                }
                clearPendingMedia()
            } else if playlist.isExtended == false, let url = URL(string: line) {
                playlist.media.append(Media(title: url.lastPathComponent, url: url, contentType: .other))
            }
        }

        if let pendingMedia, !options.skipsInvalidMedia {
            throw M3UDecodingError.missingMediaURL(title: pendingMedia.title, line: pendingMedia.line)
        }

        return playlist
    }

    private func normalizedLine(_ line: String) -> String {
        if options.trimsWhitespace {
            line.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            line.trimmingCharacters(in: .newlines)
        }
    }

    private func parseEXTINF(_ line: String, lineNumber: Int) -> PendingMedia {
        let body = line.removingPrefix("#EXTINF:")
        let pieces = body.splitOnce(separator: ",")
        let metadata = pieces.left
        let title = pieces.right?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tokens = metadata.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let duration = tokens.first.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let attributeSource = tokens.dropFirst().first.map(String.init) ?? ""
        let attributes = AttributeParser.parse(attributeSource)

        return PendingMedia(title: title, duration: duration, attributes: attributes, line: lineNumber)
    }

    private mutating func parseTag(_ line: String) {
        if line.hasPrefix("#EXTVLCOPT:") {
            parseVLCOption(String(line.removingPrefix("#EXTVLCOPT:")))
            return
        }

        if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
            let value = String(line.removingPrefix("#EXT-X-PLAYLIST-TYPE:")).uppercased()
            playlist.playlistType = HLSPlaylistType(rawValue: value)
            playlist.tags.append(PlaylistTag(name: "EXT-X-PLAYLIST-TYPE", value: value))
            return
        }

        if line.hasPrefix("#EXT-X-TARGETDURATION:") {
            let value = String(line.removingPrefix("#EXT-X-TARGETDURATION:"))
            playlist.targetDuration = Double(value)
            playlist.tags.append(PlaylistTag(name: "EXT-X-TARGETDURATION", value: value))
            return
        }

        if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
            let value = String(line.removingPrefix("#EXT-X-MEDIA-SEQUENCE:"))
            playlist.mediaSequence = Int(value)
            playlist.tags.append(PlaylistTag(name: "EXT-X-MEDIA-SEQUENCE", value: value))
            return
        }

        if line == "#EXT-X-ENDLIST" {
            playlist.hasEndList = true
            playlist.tags.append(PlaylistTag(name: "EXT-X-ENDLIST"))
            return
        }

        if line.hasPrefix("#EXT-X-KEY:") {
            let attributes = AttributeParser.parse(line.removingPrefix("#EXT-X-KEY:"))
            currentKey = HLSKey(
                method: attributes.normalizedValue(for: "METHOD"),
                uri: attributes.normalizedURL(for: "URI"),
                iv: attributes.normalizedValue(for: "IV"),
                attributes: attributes
            )
            pendingTags.append(PlaylistTag(name: "EXT-X-KEY", attributes: attributes))
            return
        }

        if line.hasPrefix("#EXT-X-BYTERANGE:") {
            let value = String(line.removingPrefix("#EXT-X-BYTERANGE:"))
            currentByteRange = parseByteRange(value)
            pendingTags.append(PlaylistTag(name: "EXT-X-BYTERANGE", value: value))
            return
        }

        if line.hasPrefix("#EXT-X-MAP:") {
            let attributes = AttributeParser.parse(line.removingPrefix("#EXT-X-MAP:"))
            currentMap = HLSMap(
                uri: attributes.normalizedURL(for: "URI"),
                byteRange: attributes.normalizedValue(for: "BYTERANGE").flatMap(parseByteRange),
                attributes: attributes
            )
            pendingTags.append(PlaylistTag(name: "EXT-X-MAP", attributes: attributes))
            return
        }

        if line == "#EXT-X-DISCONTINUITY" {
            hasPendingDiscontinuity = true
            pendingTags.append(PlaylistTag(name: "EXT-X-DISCONTINUITY"))
            return
        }

        if line.hasPrefix("#EXT-X-SESSION-DATA:") {
            let value = String(line.removingPrefix("#EXT-X-SESSION-DATA:"))
            playlist.tags.append(PlaylistTag(name: "EXT-X-SESSION-DATA", value: value, attributes: AttributeParser.parse(value)))
            return
        }

        if line.hasPrefix("#EXT-X-MEDIA:") {
            let attributes = AttributeParser.parse(line.removingPrefix("#EXT-X-MEDIA:"))
            playlist.tags.append(PlaylistTag(name: "EXT-X-MEDIA", attributes: attributes))
            return
        }

        let body = line.removingPrefix("#")
        let split = body.splitOnce(separator: ":")
        playlist.tags.append(PlaylistTag(name: split.left, value: split.right))
    }

    private func parseByteRange(_ value: String) -> ByteRange? {
        let pieces = value.splitOnce(separator: "@")
        guard let length = Int(pieces.left) else { return nil }
        return ByteRange(length: length, offset: pieces.right.flatMap(Int.init))
    }

    /// Records one `#EXTVLCOPT:` key/value pair for the media entry that follows. The body arrives without the
    /// leading `#EXTVLCOPT:`; a missing `=` yields an empty value, and surrounding quotes are stripped.
    private mutating func parseVLCOption(_ body: String) {
        let pieces = body.splitOnce(separator: "=")
        let key = pieces.left.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false else { return }
        let rawValue = pieces.right?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pendingVLCOptions[key] = rawValue.unquoted()
    }

    private func buildMedia(from pending: PendingMedia, urlString: String, lineNumber: Int) throws -> Media? {
        guard let url = URL(string: urlString) else {
            if options.skipsInvalidMedia { return nil }
            throw M3UDecodingError.invalidMediaURL(urlString, line: lineNumber)
        }

        let group = pending.attributes.normalizedValue(for: "group-title")
            ?? pending.attributes.normalizedValue(for: "group_id")
            ?? pendingGroup
        let series = SeriesInfo(title: pending.title)
        let contentType = MediaClassifier.classify(
            title: pending.title,
            url: url,
            attributes: pending.attributes,
            group: group,
            isVODPlaylist: playlist.playlistType == .vod || playlist.hasEndList,
            series: series
        )
        let hls = MediaHLSMetadata(
            key: currentKey,
            byteRange: currentByteRange,
            map: currentMap,
            hasDiscontinuity: hasPendingDiscontinuity,
            tags: pendingTags
        )

        return Media(
            title: pending.title,
            url: url,
            duration: pending.duration,
            attributes: pending.attributes,
            contentType: contentType,
            series: series,
            group: group,
            hls: hls,
            vlcOptions: pendingVLCOptions
        )
    }

    private mutating func clearPendingMedia() {
        pendingMedia = nil
        pendingGroup = nil
        currentByteRange = nil
        hasPendingDiscontinuity = false
        pendingTags = []
        pendingVLCOptions = [:]
    }
}

private enum AttributeParser {
    static func parse(_ input: some StringProtocol) -> [String: String] {
        var attributes: [String: String] = [:]
        let characters = Array(input)
        var index = characters.startIndex

        while index < characters.endIndex {
            skipSeparators(in: characters, index: &index)
            guard index < characters.endIndex else { break }

            let keyStart = index
            while index < characters.endIndex,
                  characters[index] != "=",
                  characters[index] != " ",
                  characters[index] != "\t",
                  characters[index] != "," {
                index += 1
            }

            let key = String(characters[keyStart..<index])
            skipWhitespace(in: characters, index: &index)
            guard index < characters.endIndex, characters[index] == "=" else {
                skipUntilSeparator(in: characters, index: &index)
                continue
            }

            index += 1
            skipWhitespace(in: characters, index: &index)

            let value: String
            if index < characters.endIndex, characters[index] == "\"" {
                index += 1
                let valueStart = index
                while index < characters.endIndex, characters[index] != "\"" {
                    index += 1
                }
                value = String(characters[valueStart..<index])
                if index < characters.endIndex {
                    index += 1
                }
            } else {
                let valueStart = index
                while index < characters.endIndex,
                      characters[index] != " ",
                      characters[index] != "\t",
                      characters[index] != "," {
                    index += 1
                }
                value = String(characters[valueStart..<index])
            }

            if !key.isEmpty {
                attributes[key] = value
            }
        }

        return attributes
    }

    private static func skipSeparators(in characters: [Character], index: inout Array<Character>.Index) {
        while index < characters.endIndex,
              characters[index] == " " || characters[index] == "\t" || characters[index] == "," {
            index += 1
        }
    }

    private static func skipWhitespace(in characters: [Character], index: inout Array<Character>.Index) {
        while index < characters.endIndex,
              characters[index] == " " || characters[index] == "\t" {
            index += 1
        }
    }

    private static func skipUntilSeparator(in characters: [Character], index: inout Array<Character>.Index) {
        while index < characters.endIndex,
              characters[index] != " ",
              characters[index] != "\t",
              characters[index] != "," {
            index += 1
        }
    }
}

private extension StringProtocol {
    func removingPrefix(_ prefix: String) -> SubSequence {
        hasPrefix(prefix) ? dropFirst(prefix.count) : self[...]
    }

    func unquoted() -> String {
        guard count >= 2, first == "\"", last == "\"" else { return String(self) }
        return String(dropFirst().dropLast())
    }

    func splitOnce(separator: Character) -> (left: String, right: String?) {
        var isQuoted = false

        for index in indices {
            let character = self[index]
            if character == "\"" {
                isQuoted.toggle()
            } else if character == separator, !isQuoted {
                return (
                    String(self[..<index]),
                    String(self[self.index(after: index)...])
                )
            }
        }

        return (String(self), nil)
    }
}
