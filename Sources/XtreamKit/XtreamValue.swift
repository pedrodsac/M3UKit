import Foundation

/// Panels return JSON with no reliable types: any scalar can be a string, a number, `null` or `""`, booleans arrive
/// as `0`/`1`, `"0"`/`"1"` or `true`/`false`, and PHP encodes a missing object as `[]`. These readers take whichever
/// form arrives and give back a plain value, or nil when the field is absent or empty. They never throw, so one odd
/// field doesn't lose the whole item.
extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return XtreamValue.normalized(value) }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return XtreamValue.int(from: value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return XtreamValue.int(from: value) }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return XtreamValue.double(from: value) }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return XtreamValue.bool(from: value) }
        return nil
    }

    /// A four-digit year from a field that holds a year, a full date, or free text around one.
    func lenientYear(_ key: Key) -> Int? {
        lenientString(key).flatMap(XtreamValue.year(in:))
    }

    /// `backdrop_path` is an array of URLs, a single URL, or `""`.
    func lenientStrings(_ key: Key) -> [String] {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.compactMap(XtreamValue.normalized)
        }
        return lenientString(key).map { [$0] } ?? []
    }

    /// `category_ids` is an array of numbers, but a number or a string of them also turns up.
    func lenientInts(_ key: Key) -> [Int] {
        if let values = try? decodeIfPresent([Lossy<Int>].self, forKey: key) {
            return values.compactMap(\.value)
        }
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.compactMap(XtreamValue.int(from:))
        }
        return lenientInt(key).map { [$0] } ?? []
    }

    /// The first of several names a field goes by, such as `release_date` and `releasedate`.
    func firstString(_ keys: Key...) -> String? {
        keys.lazy.compactMap { lenientString($0) }.first
    }
}

/// Decodes a value or nothing, so one malformed element doesn't fail the array it is in.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) {
        value = try? Value(from: decoder)
    }
}

enum XtreamValue {
    static func normalized(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "null" { return nil }
        return trimmed
    }

    static func int(from string: String) -> Int? {
        guard let string = normalized(string) else { return nil }
        if let value = Int(string) { return value }
        return Double(string).flatMap(int(from:))
    }

    static func int(from value: Double) -> Int? {
        value.isFinite && abs(value) < 9e18 ? Int(value) : nil
    }

    static func double(from string: String) -> Double? {
        normalized(string).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    static func bool(from string: String) -> Bool? {
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": true
        case "0", "false", "no", "off": false
        default: nil
        }
    }

    static func year(in string: String) -> Int? {
        let characters = Array(string)
        guard characters.count >= 4 else { return nil }

        for start in 0...(characters.count - 4) {
            let window = characters[start..<start + 4]
            guard window.allSatisfy({ $0.isASCII && $0.isNumber }),
                  start == 0 || characters[start - 1].isNumber == false,
                  start + 4 == characters.count || characters[start + 4].isNumber == false,
                  let year = Int(String(window)), (1900...2100).contains(year) else { continue }
            return year
        }
        return nil
    }

    /// EPG titles and descriptions arrive as base64. A value that isn't base64 for valid text is returned as it was
    /// written, because some panels send plain text and a word like "News" is also valid base64.
    static func decodeBase64Text(_ string: String) -> String {
        let compact = string.filter { $0.isWhitespace == false }
        guard compact.isEmpty == false else { return string }

        var base64 = compact.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard base64.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=") }) else {
            return string
        }

        let padding = (4 - base64.filter { $0 != "=" }.count % 4) % 4
        base64 = base64.filter { $0 != "=" } + String(repeating: "=", count: padding)

        guard let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .utf8),
              text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\r" && $0 != "\t" }) == false
        else { return string }
        return text
    }

    /// The Unix time of an EPG field that is a number, or nil for a date string, whose time zone is the panel's.
    static func unixTime(_ string: String?) -> Int? {
        guard let string, string.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(string)
    }
}

/// A list the panel sent, and how many of its items couldn't be read.
public struct XtreamList<Item: Sendable>: Sendable {
    public var items: [Item]
    public var droppedCount: Int

    public init(items: [Item], droppedCount: Int = 0) {
        self.items = items
        self.droppedCount = droppedCount
    }
}

extension XtreamList where Item: Decodable {
    /// PHP encodes an array whose keys aren't a plain sequence as an object, so a list arrives as an array or as an
    /// object of items. Items that can't be read are skipped and counted.
    static func decode(_ data: Data) throws -> XtreamList {
        let decoder = JSONDecoder()
        let lossy: [Lossy<Item>]
        if let array = try? decoder.decode([Lossy<Item>].self, from: data) {
            lossy = array
        } else {
            let object = try decoder.decode([String: Lossy<Item>].self, from: data)
            lossy = object.sorted { lhs, rhs in
                if let left = Int(lhs.key), let right = Int(rhs.key) { return left < right }
                return lhs.key < rhs.key
            }.map(\.value)
        }

        let items = lossy.compactMap(\.value)
        return XtreamList(items: items, droppedCount: lossy.count - items.count)
    }
}

func requiredKey<Value>(_ value: Value?, _ key: some CodingKey, in container: some KeyedDecodingContainerProtocol) throws -> Value {
    guard let value else {
        throw DecodingError.keyNotFound(key, .init(codingPath: container.codingPath, debugDescription: "No usable value for \(key.stringValue)."))
    }
    return value
}
