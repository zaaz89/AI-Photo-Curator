import AppKit
import CuratorCore
import SwiftUI

// MARK: look

/// One accent per guide step, used for its icon, progress and highlights.
extension GuideStep {
    var tint: Color {
        switch self {
        case .selection: .blue
        case .story: .purple
        case .export: .green
        }
    }
}

/// People get a colour by their place in the album, so the same person has the same colour everywhere.
let personColors: [Color] = [.blue, .pink, .orange, .teal, .purple, .green, .indigo, .red]
func personColor(_ index: Int) -> Color { personColors[abs(index) % personColors.count] }

/// A raised card: soft fill, hairline edge, gentle shadow; lifts a little under the pointer when `hover`.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 22
    var hover = false
    var highlight: Color? = nil
    @State private var over = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(highlight.map { AnyShapeStyle($0.opacity(0.65)) } ?? AnyShapeStyle(.separator.opacity(0.6)),
                                  lineWidth: highlight == nil ? 0.5 : 1.5)
            }
            .shadow(color: .black.opacity(over ? 0.18 : 0.08), radius: over ? 18 : 8, y: over ? 8 : 3)
            .scaleEffect(over && !reduceMotion ? 1.012 : 1)
            .animation(Motion.animation(.quick, reduceMotion: reduceMotion), value: over)
            .onHover { if hover { over = $0 } }
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

// MARK: step frame

/// The four steps as a connected bar; every step can be opened at any time.
struct StepBar: View {
    @EnvironmentObject var library: LibraryModel
    let current: GuideStep?

    var body: some View {
        let states = library.stepStates
        HStack(spacing: 0) {
            ForEach(GuideStep.allCases) { s in
                let st = states[s] ?? StepState(done: false, waiting: 0)
                Button { withMotion(.settle) { library.destination = .step(s) } } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(s == current ? AnyShapeStyle(s.tint.gradient) : AnyShapeStyle(.fill.tertiary))
                            if st.done && s != current {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(s.tint)
                            } else {
                                Text("\(s.number)").font(.callout.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(s == current ? .white : .secondary)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(library.tr("step_" + s.rawValue))
                            .font(.callout.weight(s == current ? .semibold : .regular))
                            .foregroundStyle(s == current ? .primary : .secondary)
                        if st.waiting > 0 && s != current {
                            Text("\(st.waiting)").font(.caption2.weight(.bold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.2), in: .capsule).foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.number). " + library.tr("step_" + s.rawValue))
                .accessibilityAddTraits(s == current ? .isSelected : [])
                if s != .export {
                    Capsule().fill(st.done ? AnyShapeStyle(s.tint.opacity(0.6)) : AnyShapeStyle(.separator))
                        .frame(height: 2).frame(minWidth: 16, maxWidth: 48)
                }
            }
        }
    }
}

/// The frame of a step page: step bar, title and what the AI did, the content, and a floating
/// bar at the bottom with back, what is still open and Next.
struct StepPage<Content: View>: View {
    @EnvironmentObject var library: LibraryModel
    /// nil: the People & clocks page, which is not one of the steps (no step bar; Done goes back to the album).
    let step: GuideStep?
    var lead: String
    var status: String? = nil
    var scrolls = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            if scrolls {
                ScrollView {
                    content().padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 110)
                        .frame(maxWidth: 1180).frame(maxWidth: .infinity)
                }
            } else {
                content().padding(.horizontal, 24).padding(.bottom, 84)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            }
        }
        .overlay(alignment: .bottom) { bottomBar.padding(.bottom, 18) }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            if step != nil { StepBar(current: step) }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: step?.symbol ?? "person.2.crop.square.stack").font(.title.weight(.semibold))
                    .foregroundStyle((step?.tint ?? .teal).gradient)
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.map { library.tr("stepTitle_" + $0.rawValue) } ?? library.tr("stepTitle_photos")).font(.system(size: 30, weight: .bold))
                    Text(lead).font(.title3).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 14)
        .frame(maxWidth: 1180 + 64, alignment: .leading).frame(maxWidth: .infinity)
    }

    /// Next step (or Back to album on the last step and on People & Clocks); ⌘Return.
    var nextButton: some View {
        Button {
            withMotion(.settle) { if let step { library.finishStep(step) } else { library.finishPeople() } }
        } label: {
            Label(step?.next.map { String(format: library.tr("nextStep"), library.tr("step_" + $0.rawValue)) } ?? library.tr("backToAlbum"),
                  systemImage: step?.next == nil ? "house" : "chevron.right")
                .labelStyle(TrailingIconLabel())
                .padding(.horizontal, 6)
        }
        .keyboardShortcut(.return, modifiers: .command)
    }

    var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    withMotion(.settle) { library.destination = step?.previous.map { .step($0) } ?? .home }
                } label: {
                    Label(step?.previous.map { library.tr("step_" + $0.rawValue) } ?? library.tr("albumHome"), systemImage: "chevron.left")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glass).controlSize(.large)
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.horizontal, 6)
                        .contentTransition(.numericText())
                }
                // One primary action per screen (M12e, #16): on Export the page's own Export button is the primary,
                // so "Back to album" is secondary there.
                if step == .export {
                    nextButton.buttonStyle(.glass).controlSize(.large)
                } else {
                    nextButton.buttonStyle(.glassProminent).controlSize(.large)
                }
            }
        }
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
            Text("\(Int(library.job.progress))%").font(.system(size: compact ? 22 : 30, weight: .semibold, design: .rounded))
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
        .accessibilityLabel(state == "closed" ? "eyes closed" : (state == "unsure" ? "eyes unclear" : "eyes open"))
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
