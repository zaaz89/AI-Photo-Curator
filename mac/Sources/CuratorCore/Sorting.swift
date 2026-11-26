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
    /// Everything fits the rect at `minHeight` or more (M14c). When false the stage shows its scrolling grid
    /// instead, so photos never run over the trays below.
    public var fits = true
    public init() {}
}

/// Days flow one after another like words in a paragraph: a day begins with its label above its first photo,
/// a wider gap separates days, rows wrap. The tile height is the largest (up to `maxHeight`) that fits `rect`.
/// M14c: only a row where a day begins reserves the label's height, and the gaps shrink with small tiles, so
/// more photos fit before the stage gives up; below `minHeight` the result says `fits == false` (laid out at
/// `minHeight`, taller than the rect) and the caller must scroll or clip instead of drawing over what is below.
public func stageFlow(_ items: [StageItem], in rect: CGRect, maxHeight: CGFloat, minHeight: CGFloat = 28,
                      gap: CGFloat = 8, dayGap: CGFloat = 30, labelHeight: CGFloat = 24, rowGap: CGFloat = 12) -> StageFlow {
    func place(_ h: CGFloat) -> StageFlow {
        var out = StageFlow()
        out.tileHeight = h
        let g = min(gap, max(3, h * 0.12)), rg = min(rowGap, max(4, h * 0.2))
        // Pass 1: rows (x positions only).
        struct Cell { let id: Int; let x: CGFloat; let w: CGFloat; let day: String? }
        var rows: [[Cell]] = [[]]
        var x: CGFloat = 0, lastDay: String?
        for it in items {
            let w = min(rect.width, h * CGFloat(max(0.4, min(2.5, it.aspect))))
            let newDay = it.day != lastDay
            let lead: CGFloat = x == 0 ? 0 : (newDay ? dayGap : g)
            if x > 0 && x + lead + w > rect.width {
                rows.append([]); x = 0
            } else {
                x += lead
            }
            rows[rows.count - 1].append(Cell(id: it.id, x: x, w: w, day: newDay ? it.day : nil))
            if newDay { lastDay = it.day }
            x += w
        }
        // Pass 2: a row with a day label is taller by the label.
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() where !row.isEmpty {
            let label = row.contains { $0.day != nil } ? labelHeight : 0
            for c in row {
                if let d = c.day { out.days.append((d, CGPoint(x: rect.minX + c.x, y: rect.minY + y))) }
                out.slots[c.id] = CGRect(x: rect.minX + c.x, y: rect.minY + y + label, width: c.w, height: h)
            }
            y += label + h
            if i < rows.count - 1 { y += rg }
        }
        out.height = items.isEmpty ? 0 : y
        return out
    }
    guard !items.isEmpty, rect.width > 0 else { return StageFlow() }
    let top = place(maxHeight)
    if top.height <= rect.height { return top }
    var lo = minHeight, hi = maxHeight
    let floor = place(lo)
    if floor.height > rect.height {
        var f = floor
        f.fits = false
        return f
    }
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
