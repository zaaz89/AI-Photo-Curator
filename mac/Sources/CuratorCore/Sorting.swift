import CoreGraphics
import Foundation

/// The sorting stage (M12): where a photo ends up once its results are known, and how the album is laid out
/// while photos fly in. Pure functions, so the stage and the tests agree.

/// album: in the album. check: in the album, but worth a look (closed eyes, a screenshot or document).
/// removed: blurry, a screenshot, or left out by the owner. stacked: another frame of a moment whose best frame is in the album.
public enum SortVerdict: String, CaseIterable, Sendable {
    case album, check, removed, stacked
}

/// Same rule as the export (`goesToAlbumDespiteFocus`): what is not exported is removed or stacked, what is
/// exported is in the album, flagged when it has a real problem to look at.
public func sortVerdict(_ p: Photo) -> SortVerdict {
    if !p.goesToAlbumDespiteFocus {
        if !p.rejected && p.isExtraFrame && p.focus?.tier != "blurry" { return .stacked }
        return .removed
    }
    return needsALook(p) && !p.favorite && !p.keep ? .check : .album
}

/// The analysis has judged this photo (videos have no focus check).
public func hasResults(_ p: Photo) -> Bool { p.isVideo || p.focus != nil }

/// Why a removed or flagged photo is where it is, as a reason code (`why2_…` strings, `leftOut`).
public func sortReason(_ p: Photo) -> String? {
    switch sortVerdict(p) {
    case .album: return nil
    case .removed:
        if p.rejected { return "leftOut" }
        if p.screenshot && !p.keep { return "screenshot" }
        let blur = reviewReasons(p).first { ["movement_blur", "subject_blurry", "whole_blurry"].contains($0) }
        return blur ?? "whole_blurry"
    case .stacked: return "extra_frame"
    case .check: return reviewReasons(p).first { $0 != "eyes_unsure" && $0 != "extra_frame" }
    }
}

public struct StageItem: Sendable {
    public let id: Int
    public let day: String
    public let aspect: Double
    public init(id: Int, day: String, aspect: Double) { self.id = id; self.day = day; self.aspect = aspect }
}

public struct StageFlow: Sendable {
    public var slots: [Int: CGRect] = [:]
    /// Where each day's label sits (top left of its first photo, above it).
    public var days: [(day: String, origin: CGPoint)] = []
    public var tileHeight: CGFloat = 0
    public var height: CGFloat = 0
}

/// Days flow one after another like words in a paragraph: a day begins with its label above its first photo,
/// a wider gap separates days, rows wrap. The tile height is the largest (up to `maxHeight`) that fits `rect`;
/// below `minHeight` the flow grows past the bottom instead of shrinking further.
public func stageFlow(_ items: [StageItem], in rect: CGRect, maxHeight: CGFloat, minHeight: CGFloat = 28,
                      gap: CGFloat = 8, dayGap: CGFloat = 30, labelHeight: CGFloat = 24, rowGap: CGFloat = 12) -> StageFlow {
    func place(_ h: CGFloat) -> StageFlow {
        var out = StageFlow()
        out.tileHeight = h
        var x: CGFloat = 0, y: CGFloat = 0, lastDay: String?
        for it in items {
            let w = min(rect.width, h * CGFloat(max(0.4, min(2.5, it.aspect))))
            let newDay = it.day != lastDay
            let lead: CGFloat = x == 0 ? 0 : (newDay ? dayGap : gap)
            if x > 0 && x + lead + w > rect.width {
                x = 0; y += labelHeight + h + rowGap
            } else {
                x += lead
            }
            if newDay { out.days.append((it.day, CGPoint(x: rect.minX + x, y: rect.minY + y))); lastDay = it.day }
            out.slots[it.id] = CGRect(x: rect.minX + x, y: rect.minY + y + labelHeight, width: w, height: h)
            x += w
        }
        out.height = items.isEmpty ? 0 : y + labelHeight + h
        return out
    }
    guard !items.isEmpty, rect.width > 0 else { return StageFlow() }
    let top = place(maxHeight)
    if top.height <= rect.height { return top }
    var lo = minHeight, hi = maxHeight
    if place(lo).height > rect.height { return place(lo) }
    for _ in 0..<18 {
        let mid = (lo + hi) / 2
        if place(mid).height <= rect.height { lo = mid } else { hi = mid }
    }
    return place(lo)
}

/// A pause between two steps of the stage: shorter when there are many, so the whole act stays near `total`.
public func stagger(_ count: Int, total: Double, min lower: Double = 0.012, max upper: Double = 0.12) -> Double {
    guard count > 0 else { return 0 }
    return Swift.min(upper, Swift.max(lower, total / Double(count)))
}

/// The marks that bring a photo back into the album by the export's rule: not left out; another frame of a
/// moment or a screenshot as "keep too"; a blurry one with the owner's focus mark "soft" (all that apply).
public func putBackMarks(_ p: Photo) -> [String: MarkValue] {
    var m: [String: MarkValue] = ["rejected": .bool(false)]
    if p.favorite { return m }
    if (p.isExtraFrame || p.screenshot) && !p.keep { m["keep"] = .bool(true) }
    if p.focus?.tier == "blurry" { m["focus"] = .string("soft") }
    return m
}
