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

    func image(for url: URL, side: CGFloat) async -> NSImage? {
        let bucket = side <= 260 ? 260 : (side <= 520 ? 520 : (side <= 1024 ? 1024 : 2048))          // few sizes, many hits
        let key = "\(url.path)#\(bucket)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        await acquire()
        defer { release() }
        if Task.isCancelled { return nil }
        if let hit = cache.object(forKey: key) { return hit }      // made by another request while waiting
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: bucket, height: bucket), scale: scale,
                                               representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) else { return nil }
        let img = rep.nsImage
        cache.setObject(img, forKey: key)
        return img
    }
}

struct Thumbnail: View {
    let url: URL
    var side: CGFloat = 260
    var fill = true
    @State private var image: NSImage?
    @State private var missing = false

    var body: some View {
        Rectangle().fill(.fill.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit).transition(.opacity)
                } else if missing {
                    Image(systemName: "photo.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
                }
            }
            .clipped()
            .task(id: "\(url.path)#\(side)") {
                let img = await ThumbnailCache.shared.image(for: url, side: side)
                if Task.isCancelled { return }                  // scrolled away: not "missing"
                withMotion(.fade) { image = img; missing = img == nil }
            }
    }
}
