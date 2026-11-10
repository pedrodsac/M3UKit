import Foundation

public enum XtreamAccountStatus: Codable, Hashable, Sendable {
    case active
    case banned
    case disabled
    case expired
    /// What XC 1.6 answers for a wrong username or password.
    case inactive
    case other(String)

    public init(_ rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "active": self = .active
        case "banned": self = .banned
        case "disabled": self = .disabled
        case "expired": self = .expired
        case "inactive": self = .inactive
        default: self = .other(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .active: "Active"
        case .banned: "Banned"
        case .disabled: "Disabled"
        case .expired: "Expired"
        case .inactive: "Inactive"
        case let .other(value): value
        }
    }
}

/// What the panel says about a line: `user_info` and `server_info` from the no-action `player_api.php` call, with
/// their types made plain. The password isn't kept.
public struct XtreamAccountInfo: Codable, Hashable, Sendable {
    public var username: String?
    /// The provider's broadcast message.
    public var message: String?
    public var isAuthenticated: Bool
    public var status: XtreamAccountStatus?
    /// Unix seconds. Nil for a line that doesn't expire.
    public var expiresAt: Int?
    public var isTrial: Bool
    public var activeConnections: Int?
    public var maxConnections: Int?
    /// Unix seconds.
    public var createdAt: Int?
    /// Containers the line may request (`m3u8`, `ts`, `rtmp`). Empty when the panel doesn't say.
    public var allowedOutputFormats: [String]

    public var serverURL: String?
    public var serverPort: Int?
    public var httpsPort: Int?
    public var serverProtocol: String?
    public var rtmpPort: Int?
    /// The panel's own time zone, as an identifier such as `Europe/London`.
    public var timeZoneID: String?
    /// The panel's clock, in Unix seconds, for working out how far it is from this device's.
    public var serverTimestamp: Int?
    public var isXUI: Bool
    public var version: String?
    public var revision: String?

    public var expirationDate: Date? {
        expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var creationDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var timeZone: TimeZone? {
        timeZoneID.flatMap(TimeZone.init(identifier:))
    }

    public func isExpired(at date: Date = .now) -> Bool {
        if status == .expired { return true }
        return expirationDate.map { $0 <= date } ?? false
    }

    /// Whether live streams can be asked for as HLS. A panel that doesn't list formats is assumed to allow it.
    public var allowsHLS: Bool {
        allowedOutputFormats.isEmpty || allowedOutputFormats.contains { $0.lowercased() == "m3u8" }
    }

    /// The container to ask live streams for: HLS when the line allows it, otherwise raw transport stream.
    public var preferredLiveExtension: String {
        allowsHLS ? "m3u8" : "ts"
    }

    /// Throws the reason a line can't be used: rejected, banned, disabled or expired.
    public func requireUsable(at date: Date = .now) throws {
        switch status {
        case .banned: throw XtreamError.accountBanned
        case .disabled: throw XtreamError.accountDisabled
        case .expired: throw XtreamError.accountExpired(expirationDate)
        default: break
        }

        guard isAuthenticated else { throw XtreamError.accountRejected }
        if isExpired(at: date) { throw XtreamError.accountExpired(expirationDate) }
    }
}

struct XtreamAccountResponse: Decodable {
    let info: XtreamAccountInfo

    private enum RootKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }

    private enum UserKeys: String, CodingKey {
        case username, message, auth, status
        case expiresAt = "exp_date"
        case isTrial = "is_trial"
        case activeConnections = "active_cons"
        case maxConnections = "max_connections"
        case createdAt = "created_at"
        case allowedOutputFormats = "allowed_output_formats"
    }

    private enum ServerKeys: String, CodingKey {
        case url, port, timezone, xui, version, revision
        case httpsPort = "https_port"
        case serverProtocol = "server_protocol"
        case rtmpPort = "rtmp_port"
        case serverTimestamp = "timestamp_now"
    }

    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let user = try root.nestedContainer(keyedBy: UserKeys.self, forKey: .userInfo)
        let server = try? root.nestedContainer(keyedBy: ServerKeys.self, forKey: .serverInfo)

        let status = user.lenientString(.status).map(XtreamAccountStatus.init)
        // XC 1.6 omits `auth` from some answers; a line whose status is active is plainly authenticated.
        let isAuthenticated = user.lenientBool(.auth) ?? (status == .active)

        // 0 means no expiry on some panels, as does null.
        let expiresAt = user.lenientInt(.expiresAt).flatMap { $0 > 0 ? $0 : nil }

        info = XtreamAccountInfo(
            username: user.lenientString(.username),
            message: user.lenientString(.message),
            isAuthenticated: isAuthenticated,
            status: status,
            expiresAt: expiresAt,
            isTrial: user.lenientBool(.isTrial) ?? false,
            activeConnections: user.lenientInt(.activeConnections),
            maxConnections: user.lenientInt(.maxConnections),
            createdAt: user.lenientInt(.createdAt),
            allowedOutputFormats: user.lenientStrings(.allowedOutputFormats),
            serverURL: server?.lenientString(.url),
            serverPort: server?.lenientInt(.port),
            httpsPort: server?.lenientInt(.httpsPort),
            serverProtocol: server?.lenientString(.serverProtocol),
            rtmpPort: server?.lenientInt(.rtmpPort),
            timeZoneID: server?.lenientString(.timezone),
            serverTimestamp: server?.lenientInt(.serverTimestamp),
            isXUI: server?.lenientBool(.xui) ?? false,
            version: server?.lenientString(.version),
            revision: server?.lenientString(.revision)
        )
    }
}
