import Foundation

// M12d (UX audit #12, #19): real 100% zoom (shared by the single review and Survey, M14c).
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
