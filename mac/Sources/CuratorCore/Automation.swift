import Foundation

/// Driving the app in the background while the owner keeps using the Mac (development and checks only).
/// `open -g "photocurator://…"` delivers a command without bringing the app to the front, so no mouse or
/// keyboard is taken over. The channel is off unless the user default `automation` is true:
/// `defaults write si.beehive.photocurator automation -bool true`.
///
///   photocurator://go?page=home|selection|story|export|people|all|leftOut|settings|sorting
///   photocurator://replay                                   (the sorting stage plays again)
///   photocurator://album?id=<album id>
///   photocurator://review?filter=decisions|all|leftOut      photocurator://review?close=1
///   photocurator://key?k=right|left|back|skip|favourite|faces|zoom|unzoom|keys|esc
///   photocurator://window?w=1500&h=980
///   photocurator://reload
public enum AutomationCommand: Equatable, Sendable {
    case go(String)
    case album(String)
    case review(ReviewFilter)
    case closeReview
    case key(String)
    case window(width: Double, height: Double)
    case reload
    case replay

    public static let scheme = "photocurator"
    public static let pages: Set<String> = ["home", "selection", "story", "export", "people", "all", "leftOut", "settings", "sorting"]
    public static let keys: Set<String> = ["right", "left", "back", "skip", "favourite", "faces", "zoom", "unzoom", "keys", "esc"]

    /// nil for anything that is not a known, well-formed command.
    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let q = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .compactMap { i in i.value.map { (i.name, $0) } } ?? [], uniquingKeysWith: { a, _ in a })
        switch host {
        case "go":
            guard let p = q["page"], Self.pages.contains(p) else { return nil }
            self = .go(p)
        case "album":
            guard let id = q["id"], !id.isEmpty, id.count <= 120 else { return nil }
            self = .album(id)
        case "review":
            if q["close"] != nil { self = .closeReview; return }
            self = .review(q["filter"].flatMap(ReviewFilter.init(rawValue:)) ?? .decisions)
        case "key":
            guard let k = q["k"], Self.keys.contains(k) else { return nil }
            self = .key(k)
        case "window":
            guard let w = q["w"].flatMap(Double.init), let h = q["h"].flatMap(Double.init),
                  (600...4000).contains(w), (400...3000).contains(h) else { return nil }
            self = .window(width: w, height: h)
        case "reload":
            self = .reload
        case "replay":
            self = .replay
        default:
            return nil
        }
    }
}
