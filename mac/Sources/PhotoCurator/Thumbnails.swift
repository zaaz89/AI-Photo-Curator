import AppKit
import QuickLookThumbnailing
import SwiftUI
import CuratorCore

/// Thumbnails made by macOS from the original files (read-only), cached in memory.
/// Works for HEIC, RAW and videos without going through the engine.
@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 3000 }
    /// At most this many thumbnails are made at once (M12c: thousands of grid cells must not start thousands
    /// of Quick Look requests); the others wait their turn, and a cell that scrolled away gives up its turn.
    static let maxConcurrent = 12
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if running < Self.maxConcurrent { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }    // the slot is handed over by release()
    }

    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }

    /// Why a thumbnail could not be made (M12g, audit #33): shown as a short label instead of a bare icon.
    enum Failure: Equatable { case unreadable, noPreview }

    private static func bucket(_ side: CGFloat) -> Int { side <= 260 ? 260 : (side <= 520 ? 520 : (side <= 1024 ? 1024 : 2048)) }   // few sizes, many hits

    /// A thumbnail already in memory, at the requested size or the 260 px one (a low-resolution stand-in while
    /// the large one is made). No work, no waiting.
    func cached(for url: URL, side: CGFloat) -> NSImage? {
        for b in [Self.bucket(side), 1024, 520, 260] where b <= Self.bucket(side) {
            if let hit = cache.object(forKey: "\(url.path)#\(b)" as NSString) { return hit }
        }
        return nil
    }

    func image(for url: URL, side: CGFloat) async -> NSImage? {
        if case .success(let img) = await result(for: url, side: side) { return img }
        return nil
    }

    /// The thumbnail, or the reason there is none. A cancelled request reports `.noPreview` and the caller
    /// checks `Task.isCancelled` first (as before, a cell that scrolled away is not "missing").
    func result(for url: URL, side: CGFloat) async -> Result<NSImage, Failure> {
        let bucket = Self.bucket(side)
        let key = "\(url.path)#\(bucket)" as NSString
        if let hit = cache.object(forKey: key) { return .success(hit) }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return .failure(.unreadable) }
        await acquire()
        defer { release() }
        if Task.isCancelled { return .failure(.noPreview) }
        if let hit = cache.object(forKey: key) { return .success(hit) }      // made by another request while waiting
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: bucket, height: bucket), scale: scale,
                                               representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) else { return .failure(.noPreview) }
        let img = rep.nsImage
        cache.setObject(img, forKey: key)
        return .success(img)
    }
}

struct Thumbnail: View {
    let url: URL
    var side: CGFloat = 260
    var fill = true
    @State private var image: NSImage?
    @State private var failure: ThumbnailCache.Failure?
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        Rectangle().fill(.fill.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit).transition(.opacity)
                } else if let failure {
                    // Labelled missing state with a short reason; the label drops out when the cell is too small.
                    let label = library.tr(failure == .unreadable ? "thumbUnreadable" : "thumbNoPreview")
                    ViewThatFits {
                        VStack(spacing: Space.xs) {
                            Image(systemName: "photo.badge.exclamationmark").font(.title2)
                            Text(label).font(TypeRole.caption).multilineTextAlignment(.center).lineLimit(2)
                        }
                        .padding(Space.s)
                        Image(systemName: "photo.badge.exclamationmark").font(.title2)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                } else if side > 520 {
                    // A large photo (Quick Review) that is slow: a spinner on top of the small version, if any.
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(library.tr("thumbLoading"))
                }
            }
            .clipped()
            .task(id: "\(url.path)#\(side)") {
                // The 260 px thumbnail (usually already cached by the grid) stands in while the large one is made.
                if image == nil, let low = ThumbnailCache.shared.cached(for: url, side: side) { image = low }
                let result = await ThumbnailCache.shared.result(for: url, side: side)
                if Task.isCancelled { return }                  // scrolled away: not "missing"
                withMotion(.fade) {
                    switch result {
                    case .success(let img): image = img; failure = nil
                    case .failure(let f): if image == nil { failure = f }      // keep a low-resolution stand-in
                    }
                }
            }
    }
}
