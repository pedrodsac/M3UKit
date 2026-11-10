import Foundation

/// Why a panel request didn't give usable data, in the terms an app can show.
public enum XtreamError: Error, Equatable, Sendable, LocalizedError {
    /// The server address can't be turned into a panel URL.
    case invalidServer
    /// The panel doesn't accept the username and password: `auth` is 0, or it answered `false` or nothing at all.
    case accountRejected
    case accountExpired(Date?)
    case accountDisabled
    case accountBanned
    case panelUnreachable(String)
    /// A web page came back instead of data: a reseller landing page, a Cloudflare challenge, or a wrong address.
    case panelReturnedHTML
    /// The HTTP status wasn't a success. XUI answers a wrong, disabled, banned or expired line with 404, and a panel
    /// without `player_api.php` also answers 404, so the status alone can't tell the two apart.
    case unexpectedStatus(Int)
    case emptyResponse
    /// The panel answered `false` for an action it doesn't implement.
    case unsupportedAction(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServer: "The server address isn't valid."
        case .accountRejected: "The server doesn't accept this username and password."
        case .accountExpired: "The subscription has expired."
        case .accountDisabled: "The account is disabled."
        case .accountBanned: "The account is banned."
        case let .panelUnreachable(reason): "The server can't be reached: \(reason)"
        case .panelReturnedHTML: "The server returned a web page instead of data."
        case let .unexpectedStatus(status): "The server answered with status \(status)."
        case .emptyResponse: "The server returned nothing."
        case let .unsupportedAction(action): "The server doesn't support \(action)."
        case let .decodingFailed(reason): "The server's answer couldn't be read: \(reason)"
        }
    }
}
