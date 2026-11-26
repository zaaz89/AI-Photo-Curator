import Foundation

// M12d (UX audit #12, #19, #11): real 100% zoom and the compare mode's position among the frames of a moment.
// Pure maths in points and unit coordinates, so the zoom target, clamping and panning are unit-tested.

/// A point in unit image coordinates: 0...1, origin top-left (like the engine's face boxes).
public struct ZoomPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let centre = ZoomPoint(x: 0.5, y: 0.5)
}

/// A size in points or pixels.
public struct ZoomSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public enum ZoomMath {
    /// Where Z zooms: the centre of the largest main face, else the centre of the photo.
    /// (The engine has no saliency or attention point yet; when it does, it goes here, after the face.)
    public static func target(faces: [Photo.Faces.Box]?) -> ZoomPoint {
        guard let b = mainFaces(faces ?? [], limit: 1).first else { return .centre }
        return clampUnit(ZoomPoint(x: b.x + b.w / 2, y: b.y + b.h / 2))
    }

    /// The photo fitted into the view, keeping its aspect ratio.
    public static func fit(ratio: Double, in view: ZoomSize) -> ZoomSize {
        guard ratio > 0, view.width > 0, view.height > 0 else { return ZoomSize(width: 0, height: 0) }
        return view.width / view.height > ratio
            ? ZoomSize(width: view.height * ratio, height: view.height)
            : ZoomSize(width: view.width, height: view.width / ratio)
    }

    /// How much larger than the fitted photo 100% is: one image pixel on one screen pixel. Never below 1
    /// (a photo smaller than the view is already shown at 100% or more).
    public static func actualPixelsFactor(pixelWidth: Double, fittedWidth: Double, displayScale: Double) -> Double {
        guard pixelWidth > 0, fittedWidth > 0, displayScale > 0 else { return 1 }
        return max(1, pixelWidth / displayScale / fittedWidth)
    }

    /// The centre kept so the zoomed photo always covers the view (no empty band at an edge). An axis on
    /// which the photo is not larger than the view stays centred.
    public static func clamp(_ centre: ZoomPoint, content: ZoomSize, view: ZoomSize) -> ZoomPoint {
        func axis(_ c: Double, _ content: Double, _ view: Double) -> Double {
            guard content > view, content > 0 else { return 0.5 }
            let half = view / 2 / content
            return min(max(c, half), 1 - half)
        }
        return ZoomPoint(x: axis(centre.x, content.width, view.width), y: axis(centre.y, content.height, view.height))
    }

    /// The offset of the zoomed photo from the view's centre that puts `centre` in the middle (clamped).
    public static func offset(centre: ZoomPoint, content: ZoomSize, view: ZoomSize) -> ZoomSize {
        let c = clamp(centre, content: content, view: view)
        return ZoomSize(width: (0.5 - c.x) * content.width, height: (0.5 - c.y) * content.height)
    }

    /// A drag by `translation` points moves the photo with the pointer: the centre moves the other way.
    public static func pan(_ centre: ZoomPoint, by translation: ZoomSize, content: ZoomSize, view: ZoomSize) -> ZoomPoint {
        guard content.width > 0, content.height > 0 else { return centre }
        let moved = ZoomPoint(x: centre.x - translation.width / content.width, y: centre.y - translation.height / content.height)
        return clamp(moved, content: content, view: view)
    }

    static func clampUnit(_ p: ZoomPoint) -> ZoomPoint {
        ZoomPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }
}

// MARK: compare mode

/// Two frames of a moment side by side: the keeper on the left, a challenger on the right. ←/→ change the
/// challenger, 1 or 2 picks the one for the album ("winner stays"): after a pick the next frame comes in.
public struct CompareSession: Equatable, Sendable {
    public let frames: [Int]
    public private(set) var keeper: Int
    public private(set) var challenger: Int?

    /// `keeper` defaults to the first frame; `challenger` to the frame after the keeper.
    public init(frames: [Int], keeper: Int?, challenger: Int? = nil) {
        var seen = Set<Int>()
        let unique = frames.filter { seen.insert($0).inserted }
        self.frames = unique
        let k = keeper.flatMap { unique.contains($0) ? $0 : nil } ?? unique.first ?? 0
        self.keeper = k
        if let c = challenger, c != k, unique.contains(c) {
            self.challenger = c
        } else {
            self.challenger = nil
            self.challenger = following(k)
        }
    }

    /// The frames that can be the challenger, in the moment's order.
    public var others: [Int] { frames.filter { $0 != keeper } }

    /// The challenger's place among the others, 1-based, and how many there are.
    public var position: (index: Int, count: Int) {
        let o = others
        return ((challenger.flatMap { o.firstIndex(of: $0) } ?? 0) + 1, o.count)
    }

    /// The next frame after `id` in the moment's order that is not the keeper, wrapping around.
    func following(_ id: Int, step: Int = 1) -> Int? {
        guard !frames.isEmpty else { return nil }
        let start = frames.firstIndex(of: id) ?? 0
        for i in 1...frames.count {
            let f = frames[((start + step * i) % frames.count + frames.count) % frames.count]
            if f != keeper { return f }
        }
        return nil
    }

    public mutating func next() { if let c = challenger { challenger = following(c) } }
    public mutating func previous() { if let c = challenger { challenger = following(c, step: -1) } }

    /// 1 keeps the left frame, 2 makes the right one the keeper. Returns the keeper after the pick
    /// (nil for any other number or without a challenger).
    @discardableResult
    public mutating func pick(_ side: Int) -> Int? {
        guard let c = challenger else { return side == 1 ? keeper : nil }
        switch side {
        case 1:
            challenger = following(c)
        case 2:
            keeper = c
            challenger = following(c)
        default:
            return nil
        }
        return keeper
    }
}
