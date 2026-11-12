import CuratorCore
import SwiftUI

/// The album's home: what it is, and only what still needs a decision, one card each.
struct OverviewView: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if library.job.running && library.job.collection == library.tripId { analysing }
                strip
                if let o = library.overview {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) { cards(o) }
                } else if library.photos.isEmpty && !library.job.running {
                    ContentUnavailableView(library.tr("nothingAnalysed"), systemImage: "sparkles",
                                           description: Text(library.tr("nothingAnalysedText")))
                }
            }
            .padding(28)
            .frame(maxWidth: 1200, alignment: .leading)
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(library.trips.first { $0.id == library.tripId }?.name ?? "").font(.largeTitle.weight(.bold))
            if let f = library.overview?.facts {
                Text(facts(f)).foregroundStyle(.secondary).contentTransition(.numericText())
            }
        }
    }

    func facts(_ f: Overview.Facts) -> String {
        var parts: [String] = []
        parts.append(String(format: library.tr(f.people == 1 ? "onePerson" : "people"), f.people))
        parts.append(Strings.photos(f.photos - f.videos, library.lang))
        if f.videos > 0 { parts.append(String(format: library.tr("videosN"), f.videos)) }
        if f.days > 0 { parts.append(String(format: library.tr(f.days == 1 ? "oneDay" : "daysN"), f.days)) }
        if !f.places.isEmpty { parts.append(f.places.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    var analysing: some View {
        HStack(spacing: 14) {
            AIRing(symbol: library.job.phase.symbol, size: 44, spinning: true, progress: library.job.progress / 100)
            VStack(alignment: .leading, spacing: 3) {
                Text(library.tr("phase_" + library.job.phase.rawValue)).font(.headline)
                Text(library.tr("analysingHint")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(library.job.progress))%").font(.title2.weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText(value: library.job.progress))
        }
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(AngularGradient(colors: aiGradientColors, center: .center), lineWidth: 1.5).opacity(0.7) }
        .animation(.snappy, value: library.job.progress)
    }

    /// A few of the album's photos: favourites first, then sharp ones.
    var strip: some View {
        let pick = (library.photos.filter { $0.favorite && !$0.rejected && !$0.isVideo }
                    + library.photos.filter { !$0.favorite && !$0.rejected && !$0.isVideo && $0.focus?.tier == "sharp" }
                    + library.photos.filter { !$0.rejected && !$0.isVideo }).reduce(into: [Photo]()) { acc, p in
            if !acc.contains(where: { $0.id == p.id }) { acc.append(p) }
        }
        return HStack(spacing: 10) {
            ForEach(pick.prefix(6)) { p in
                Thumbnail(url: p.fileURL, side: 520)
                    .frame(height: 150).frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 14))
                    .onTapGesture { library.destination = .all; library.click(p, modifiers: []) }
            }
        }
        .frame(height: pick.isEmpty ? 0 : 150)
    }

    @ViewBuilder func cards(_ o: Overview) -> some View {
        let s = library.steps
        AssistantCard(icon: "clock.arrow.2.circlepath", tint: .teal, title: library.tr("cardClocks"), done: s["times"] == true,
                      text: o.clocks.pending > 0 ? String(format: library.tr("clocksPending"), o.clocks.pending)
                          : o.clocks.applied > 0 ? String(format: library.tr("clocksApplied"), o.clocks.applied)
                          : library.tr("clocksOK"),
                      action: library.tr(o.clocks.pending > 0 ? "check" : "showCard"), prominent: o.clocks.pending > 0) {
            library.sheet = .clocks
        }
        AssistantCard(icon: "square.stack.3d.up", tint: .blue, title: library.tr("cardMoments"), done: s["duplicates"] == true,
                      text: o.moments.total == 0 ? library.tr("momentsNone")
                          : o.moments.needYou > 0 ? String(format: library.tr("momentsNeed"), o.moments.needYou, o.moments.decided + o.moments.chosen)
                          : String(format: library.tr("momentsDone"), o.moments.total),
                      action: o.moments.total == 0 ? nil : library.tr(o.moments.needYou > 0 ? "review" : "showCard"),
                      prominent: o.moments.needYou > 0) {
            library.sheet = .moments
        }
        AssistantCard(icon: "camera.aperture", tint: .orange, title: library.tr("cardBlurry"), done: s["blurry"] == true,
                      text: o.blurry.total == 0 ? library.tr("blurryNone")
                          : String(format: library.tr("blurrySome"), o.blurry.total, o.blurry.leftOut),
                      action: o.blurry.total == 0 ? nil : library.tr("review"), prominent: false) {
            library.destination = .blurry
        }
        AssistantCard(icon: "calendar", tint: .purple, title: library.tr("cardEvents"), done: s["events"] == true,
                      text: String(format: library.tr("eventsText"), o.events.events, o.events.days),
                      action: library.tr("browse"), prominent: false) {
            library.destination = .all
            library.markStep("events")
        }
        AssistantCard(icon: "text.bubble", tint: .pink, title: library.tr("cardDescriptions"),
                      done: o.descriptions.photos > 0 && o.descriptions.done >= o.descriptions.photos,
                      text: o.descriptions.done >= o.descriptions.photos && o.descriptions.photos > 0
                          ? String(format: library.tr("descAll"), o.descriptions.photos)
                          : String(format: library.tr("descSome"), o.descriptions.done, o.descriptions.photos, max(1, o.descriptions.minutesLeft)),
                      action: o.descriptions.done >= o.descriptions.photos ? nil : library.tr("describe"),
                      prominent: false, disabled: library.job.running) {
            library.describePhotos()
        }
        AssistantCard(icon: "square.and.arrow.up", tint: .green, title: library.tr("cardExport"), done: o.export.done,
                      text: o.export.done ? library.tr("exportDone") : String(format: library.tr("exportReady"), o.export.photos),
                      action: library.tr(o.export.done ? "exportAgain" : "exportShort"), prominent: !o.export.done,
                      disabled: library.job.running) {
            library.sheet = .export
        }
    }
}

struct AssistantCard: View {
    let icon: String
    let tint: Color
    let title: String
    var done = false
    let text: String
    let action: String?
    var prominent = false
    var disabled = false
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.title2).foregroundStyle(done ? .green : tint).frame(width: 30)
                    .contentTransition(.symbolEffect(.replace))
                Text(title).font(.headline)
            }
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            if let action {
                Group {
                    if prominent { Button(action, action: run).buttonStyle(.glassProminent) }
                    else { Button(action, action: run).buttonStyle(.glass) }
                }
                .controlSize(.large)
                .disabled(disabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 18))
        .overlay {
            if prominent { RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.5), lineWidth: 1.5) }
        }
        .accessibilityElement(children: .combine)
    }
}
