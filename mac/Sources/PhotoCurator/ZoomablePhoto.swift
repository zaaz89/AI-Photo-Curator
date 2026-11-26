import AppKit
import CuratorCore
import ImageIO
import SwiftUI

// M12d (UX audit #12, #19): real 100% zoom from the original. Z toggles between the whole photo and 100%
// (one image pixel on one screen pixel), centred on the main face; drag to look around. Only the photo on
// screen is decoded at full size, off the main thread; until it is ready the 2048 px thumbnail is shown
// enlarged with a spinner, and if the original can't be decoded that thumbnail stays (with a note).

/// A decoded original, handed from the decoding task to the view (CGImage is immutable).
final class DecodedOriginal: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

enum OriginalImage {
    /// The whole original at full resolution with its orientation applied, or nil if ImageIO can't decode it.
    /// Read only: ImageIO opens the file for reading; nothing is written or cached on disk.
    static func load(_ url: URL) async -> DecodedOriginal? {
        await Task.detached(priority: .userInitiated) { () -> DecodedOriginal? in
            let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
            let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            let side = max(width, height)
            guard side > 0 else { return nil }
            // A "thumbnail" as large as the image: the one ImageIO call that decodes RAW and HEIC alike and
            // applies the EXIF orientation.
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceShouldCacheImmediately: true,
                                            kCGImageSourceThumbnailMaxPixelSize: side]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return DecodedOriginal(image)
        }.value
    }
}

/// A photo that fits its space, or shows at 100% when `zoomed`. `centre` (unit coordinates) is what is in the
/// middle when zoomed; the compare view passes the same binding to both panes, so zoom and pan stay in sync.
struct ZoomablePhoto: View {
    @EnvironmentObject var library: LibraryModel
    let url: URL
    /// Width / height from the engine (replaced by the original's once decoded).
    let ratio: Double
    /// The original's width in pixels from the engine, for the 100% size before the original is decoded.
    let pixelWidth: Int?
    let zoomed: Bool
    @Binding var centre: ZoomPoint
    @Environment(\.displayScale) private var displayScale
    @State private var original: DecodedOriginal?
    @State private var loading = false
    @State private var failed = false
    @State private var dragStart: ZoomPoint?

    var body: some View {
        GeometryReader { g in
            let view = ZoomSize(width: Double(g.size.width), height: Double(g.size.height))
            let fitted = ZoomMath.fit(ratio: shownRatio, in: view)
            // Before the original is ready: the engine's width; without that the thumbnail's 2048 px.
            let pixels = original.map { Double($0.image.width) } ?? Double(pixelWidth ?? 2048)
            let factor = zoomed ? ZoomMath.actualPixelsFactor(pixelWidth: pixels, fittedWidth: fitted.width,
                                                             displayScale: Double(displayScale)) : 1
            let content = ZoomSize(width: fitted.width * factor, height: fitted.height * factor)
            let offset = zoomed ? ZoomMath.offset(centre: centre, content: content, view: view) : ZoomSize(width: 0, height: 0)
            ZStack {
                Thumbnail(url: url, side: 2048, fill: false)
                if zoomed, let original {
                    Image(decorative: original.image, scale: 1).resizable().interpolation(.high)
                }
            }
            .frame(width: CGFloat(content.width), height: CGFloat(content.height))
            .clipShape(.rect(cornerRadius: zoomed ? 0 : Radius.medium))
            .offset(x: CGFloat(offset.width), y: CGFloat(offset.height))
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            .contentShape(.rect)
            .gesture(drag(content: content, view: view), including: zoomed ? .all : .subviews)
            .motionAnimation(.quick, value: zoomed)
        }
        .overlay {
            if zoomed && loading {
                HStack(spacing: Space.m) {
                    ProgressView().controlSize(.small)
                    Text(library.tr("zoomLoading")).font(TypeRole.caption)
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                .background(.ultraThinMaterial, in: .capsule)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(alignment: .bottom) {
            if zoomed && failed {
                Text(library.tr("zoomFallback")).font(TypeRole.caption)
                    .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.bottom, Space.l)
            }
        }
        .task(id: zoomed) { await loadOriginal() }
    }

    var shownRatio: Double {
        guard let o = original, o.image.height > 0 else { return ratio }
        return Double(o.image.width) / Double(o.image.height)
    }

    func drag(content: ZoomSize, view: ZoomSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let start = dragStart ?? ZoomMath.clamp(centre, content: content, view: view)
                if dragStart == nil { dragStart = start }
                centre = ZoomMath.pan(start, by: ZoomSize(width: Double(v.translation.width), height: Double(v.translation.height)),
                                      content: content, view: view)
            }
            .onEnded { _ in dragStart = nil }
    }

    func loadOriginal() async {
        guard zoomed, original == nil, !failed, !loading else { return }
        loading = true
        let decoded = await OriginalImage.load(url)
        // Kept even if the zoom was turned off meanwhile: the next Z on this photo is instant.
        original = decoded
        failed = decoded == nil
        loading = false
    }
}
