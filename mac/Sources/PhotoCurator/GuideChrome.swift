import AppKit
import CuratorCore
import SwiftUI

// MARK: look

/// People get a colour by their place in the album, so the same person has the same colour everywhere.
let personColors: [Color] = [.blue, .pink, .orange, .teal, .purple, .green, .indigo, .red]
func personColor(_ index: Int) -> Color { personColors[abs(index) % personColors.count] }

/// A raised card: soft fill, hairline edge, gentle shadow; lifts a little under the pointer when `hover`
/// (the shared `.hoverLift()`, M12f).
struct CardStyle: ViewModifier {
    var radius: CGFloat = 22
    var hover = false
    var highlight: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(highlight.map { AnyShapeStyle($0.opacity(0.65)) } ?? AnyShapeStyle(.separator.opacity(0.6)),
                                  lineWidth: highlight == nil ? 0.5 : 1.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .hoverLift(hover, radius: radius)
    }
}

extension View {
    func card(radius: CGFloat = 22, hover: Bool = false, highlight: Color? = nil) -> some View {
        modifier(CardStyle(radius: radius, hover: hover, highlight: highlight))
    }
}

/// A photo that fills its frame with rounded corners. Read-only from the original file.
struct PhotoCover: View {
    let photo: Photo
    var side: CGFloat = 520
    var radius: CGFloat = 14
    var body: some View {
        Thumbnail(url: photo.fileURL, side: side)
            .clipShape(.rect(cornerRadius: radius))
            .overlay(alignment: .bottomLeading) {
                if photo.isVideo {
                    Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(6).background(.black.opacity(0.45), in: .circle).padding(6)
                }
            }
    }
}

/// One large photo and two small ones, for step and chapter cards.
struct PhotoMosaic: View {
    let photos: [Photo]
    var radius: CGFloat = 14
    var body: some View {
        let p = Array(photos.prefix(3))
        GeometryReader { g in
            HStack(spacing: 4) {
                if let first = p.first {
                    PhotoCover(photo: first, side: 520, radius: 0).frame(width: p.count > 1 ? g.size.width * 0.62 : g.size.width)
                }
                if p.count > 1 {
                    VStack(spacing: 4) {
                        ForEach(p.dropFirst(), id: \.id) { PhotoCover(photo: $0, side: 260, radius: 0) }
                    }
                }
            }
        }
        .background(.fill.quaternary)
        .clipShape(.rect(cornerRadius: radius))
    }
}

/// A round badge with a person's initials.
struct PersonBadge: View {
    let name: String
    let index: Int
    var size: CGFloat = 36
    var body: some View {
        Text(initials(name))
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(personColor(index).gradient, in: .circle)
            .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
            .accessibilityLabel(name)
    }
}

/// A section title inside a page.
struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.bold))
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: page frame

/// The frame of a secondary page of the album (Moments, Chapters, People & Clocks; opened from the View menu):
/// a title with what the app did, a status line, and the content. No steps and no Next: the album's path and its
/// one primary button live on the path itself (M14a); "Back to Album" returns there.
struct StepPage<Content: View>: View {
    @EnvironmentObject var library: LibraryModel
    let title: String
    let symbol: String
    var lead: String
    var status: String? = nil
    var scrolls = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            if scrolls {
                ScrollView {
                    content().padding(.horizontal, Space.huge).padding(.top, Space.m).padding(.bottom, Space.giant)
                        .frame(maxWidth: 1180).frame(maxWidth: .infinity)
                }
            } else {
                content().padding(.horizontal, Space.xxxl).padding(.bottom, Space.xxxl)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            }
        }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            Image(systemName: symbol).font(.title.weight(.semibold)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).scaledFont(30, weight: .bold, relativeTo: .title)
                Text(lead).font(.title3).foregroundStyle(.secondary).lineLimit(2)
                if let status {
                    Text(status).font(TypeRole.supporting).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: Space.l)
            Button { withMotion(.settle) { library.open(station: nil) } } label: {
                Label(library.tr("backToAlbum"), systemImage: "chevron.left")
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
            .help(library.tr("backToAlbum") + "  (Esc)")
        }
        .padding(.horizontal, Space.huge).padding(.top, Space.xl).padding(.bottom, Space.l)
        .frame(maxWidth: 1180 + 64, alignment: .leading).frame(maxWidth: .infinity)
    }
}

/// Text first, icon after ("Next: Story ›").
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// The live analysis, shown wherever the owner would otherwise wait for numbers.
struct AnalysisCard: View {
    @EnvironmentObject var library: LibraryModel
    var compact = false
    var body: some View {
        HStack(spacing: 16) {
            AIRing(symbol: library.job.phase.symbol, size: compact ? 40 : 56, spinning: true, progress: library.job.progress / 100)
            VStack(alignment: .leading, spacing: 4) {
                Text(library.tr("phase_" + library.job.phase.rawValue)).font(compact ? .headline : .title3.weight(.semibold))
                Text(library.tr("analysingHint")).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            Text("\(Int(library.job.progress))%").scaledFont(compact ? 22 : 30, weight: .semibold, design: .rounded, relativeTo: .title2)
                .monospacedDigit().contentTransition(.numericText(value: library.job.progress))
        }
        .padding(compact ? 14 : 20)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(AngularGradient(colors: aiGradientColors, center: .center), lineWidth: 1.5).opacity(0.75)
        }
        .motionAnimation(.settle, value: library.job.progress)
    }
}

/// An empty state that explains, with an optional action.
struct GuideEmpty: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// A face cut out of a photo (from the engine's face box), with a ring for eyes open or closed.
struct FaceCrop: View {
    let url: URL
    let box: Photo.Faces.Box
    var size: CGFloat = 58
    @EnvironmentObject private var library: LibraryModel
    @State private var image: NSImage?

    var body: some View {
        let state = eyeState(box)
        let colour: Color = state == "closed" ? .orange : (state == "unsure" ? .gray : .green)
        ZStack {
            Circle().fill(.fill.tertiary)
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(colour, lineWidth: max(2.5, size / 30)) }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: state == "closed" ? "eye.slash.fill" : (state == "unsure" ? "questionmark" : "eye.fill"))
                .font(.system(size: size * 0.18, weight: .bold)).foregroundStyle(.white)
                .padding(size * 0.06).background(colour, in: .circle)
        }
        .overlay(alignment: .bottomLeading) {
            if box.lookingAway == true {
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: size * 0.16, weight: .bold)).foregroundStyle(.white)
                    .padding(size * 0.07).background(Color.orange, in: .circle)
            }
        }
        .task(id: url.path + "\(box.x)\(box.y)") { image = await crop() }
        .accessibilityLabel(eyesLabel(state))
    }

    /// "Eyes closed" (and ", looking away"), from Strings in the app language (M12g, #23).
    func eyesLabel(_ state: String) -> String {
        let eyes = library.tr(state == "closed" ? "eyes_closed" : (state == "unsure" ? "eyes_unsure" : "eyes_open"))
        return box.lookingAway == true ? eyes + ", " + library.tr("eyes_away") : eyes
    }

    func crop() async -> NSImage? {
        guard let full = await ThumbnailCache.shared.image(for: url, side: 1024),
              let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = Double(cg.width), h = Double(cg.height)
        // A square around the face, a little wider than the box, kept inside the image.
        let side = max(box.w * w, box.h * h) * 1.6
        let cx = (box.x + box.w / 2) * w, cy = (box.y + box.h / 2) * h
        var r = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
        r = r.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !r.isEmpty, let c = cg.cropping(to: r.integral) else { return nil }
        return NSImage(cgImage: c, size: NSSize(width: c.width, height: c.height))
    }
}

/// The same people side by side in every frame of a moment: one column per frame, one row per person,
/// faces enlarged, so a blink or a look away shows at a glance. Click a column to look at that frame.
struct FaceComparison: View {
    @EnvironmentObject var library: LibraryModel
    let frames: [Photo]
    let current: Int?
    var faceSize: CGFloat = 88
    var pick: ((Photo) -> Void)? = nil

    var body: some View {
        let boxes = frames.map { $0.faces?.boxes ?? [] }
        let ref = frames.firstIndex { $0.id == current }.flatMap { boxes[$0].isEmpty ? nil : $0 }
            ?? boxes.indices.max { mainFaces(boxes[$0]).count < mainFaces(boxes[$1]).count } ?? 0
        let rows = matchFaces(boxes, reference: ref)
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(frames.enumerated()), id: \.element.id) { col, f in
                VStack(spacing: 8) {
                    // Without faces to compare, the frames themselves are shown larger.
                    PhotoCover(photo: f, side: 520, radius: 8)
                        .frame(width: rows.isEmpty ? 240 : faceSize * 1.5, height: rows.isEmpty ? 160 : faceSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(f.id == current ? Color.white : .clear, lineWidth: 3)
                        }
                        .overlay(alignment: .topLeading) {
                            Image(systemName: f.goesToAlbumDespiteFocus ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(f.goesToAlbumDespiteFocus ? Color.green : Color.gray)
                                .font(.title3).padding(4).shadow(radius: 2)
                        }
                    ForEach(rows.indices, id: \.self) { r in
                        if let b = rows[r][col] {
                            FaceCrop(url: f.fileURL, box: b, size: faceSize)
                        } else {
                            Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .frame(width: faceSize, height: faceSize)
                                .overlay { Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(.tertiary) }
                                .help(library.tr("faceNotFound"))
                        }
                    }
                }
                .padding(6)
                .background(f.id == current ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 12))
                .contentShape(.rect)
                .onTapGesture { pick?(f) }
            }
        }
    }
}
