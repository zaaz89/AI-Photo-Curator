import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Thumbnails made by macOS from the original files (read-only), cached in memory.
/// Works for HEIC, RAW and videos without going through the engine.
@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 3000 }

    func image(for url: URL, side: CGFloat) async -> NSImage? {
        let bucket = side <= 260 ? 260 : (side <= 520 ? 520 : 1024)          // few sizes, many hits
        let key = "\(url.path)#\(bucket)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
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
                withAnimation(.easeOut(duration: 0.18)) { image = img; missing = img == nil }
            }
    }
}
