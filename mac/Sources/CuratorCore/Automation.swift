import Foundation

/// Driving the app in the background while the owner keeps using the Mac (development and checks only).
/// `open -g "photocurator://…"` delivers a command without bringing the app to the front, so no mouse or
/// keyboard is taken over. The channel is off unless the user default `automation` is true:
/// `defaults write si.beehive.photocurator automation -bool true`.
///
///   photocurator://go?page=home|selection|story|export|people|all|leftOut|settings|sorting
///   (M14a: also journey|photos|analysis|questions|album for the path's stations, moments|chapters for the views;
///   the old names open the station or view that replaced them)
///   photocurator://replay                                   (the sorting stage plays again)
///   photocurator://album?id=<album id>
///   photocurator://review?filter=decisions|all|leftOut      photocurator://review?close=1
///   photocurator://key?k=right|left|back|skip|favourite|faces|zoom|unzoom|keys|esc|compare|pick1|pick2|confirm|accept
///   (keys go through `ReviewKeymap`: in Survey right/left move the focus, pick1/pick2 press 1/2, confirm is Return,
///   accept is A, skip is S; compare (C) opens Survey from the single review)
///   photocurator://window?w=1500&h=980
///   photocurator://reload
///   photocurator://firstrun?page=0|1|2                      photocurator://firstrun?close=1   (M12f)
public enum AutomationCommand: Equatable, Sendable {
    case go(String)
    case album(String)
    case review(ReviewFilter)
    case closeReview
    case key(String)
    case window(width: Double, height: Double)
    case reload
    case replay
    /// Show the first run on a page (0, 1, 2), or close it (nil).
    case firstRun(Int?)

    public static let scheme = "photocurator"
    public static let pages: Set<String> = ["home", "selection", "story", "export", "people", "all", "leftOut", "settings", "sorting",
                                            "journey", "photos", "analysis", "decisions", "questions", "album", "moments", "chapters"]
    public static let keys: Set<String> = ["right", "left", "back", "skip", "favourite", "faces", "zoom", "unzoom", "keys", "esc",
                                             "compare", "pick1", "pick2", "confirm", "accept"]

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
        case "firstrun":
            if q["close"] != nil { self = .firstRun(nil); return }
            guard let p = q["page"].flatMap(Int.init), (0...2).contains(p) else { return nil }
            self = .firstRun(p)
        default:
            return nil
        }
    }
}
