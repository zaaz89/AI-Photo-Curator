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
        let l = library.lang
        var parts = [Strings.count(f.people, .person, l), Strings.count(f.photos - f.videos, .photo, l)]
        if f.videos > 0 { parts.append(Strings.count(f.videos, .video, l)) }
        if f.days > 0 { parts.append(Strings.count(f.days, .day, l)) }
        if !f.places.isEmpty { parts.append(f.places.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    func momentsText(_ m: Overview.Moments) -> String {
        let l = library.lang
        if m.total == 0 { return library.tr("momentsNone") }
        if m.needYou == 0 { return String(format: library.tr("momentsDone"), Strings.count(m.total, .moment, l)) }
        var t = String(format: library.tr("momentsNeed"), Strings.count(m.needYou, .moment, l))
        if m.decided > 0 { t += " " + String(format: library.tr("momentsAuto"), Strings.count(m.decided, .moment, l)) }
        return t
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
        let busy = o.analysing || (library.job.running && library.job.collection == library.tripId)
        if busy {
            // Until the analysis is through, only show what is already true; no zeros that look final.
            AssistantCard(icon: "clock.arrow.2.circlepath", tint: .teal, title: library.tr("cardClocks"),
                          text: library.tr("stillAnalysing"), action: nil) {}
            AssistantCard(icon: "square.stack.3d.up", tint: .blue, title: library.tr("cardMoments"),
                          text: library.tr("stillAnalysing"), action: nil) {}
            AssistantCard(icon: "camera.aperture", tint: .orange, title: library.tr("cardBlurry"),
                          text: library.tr("stillAnalysing"), action: nil) {}
        } else {
            decisionCards(o, s)
        }
        restCards(o, s, busy: busy)
    }

    @ViewBuilder func decisionCards(_ o: Overview, _ s: [String: Bool]) -> some View {
        AssistantCard(icon: "clock.arrow.2.circlepath", tint: .teal, title: library.tr("cardClocks"), done: library.isDone("times"),
                      text: o.clocks.pending > 0 ? String(format: library.tr("clocksPending"), o.clocks.pending)
                          : o.clocks.applied > 0 ? String(format: library.tr("clocksApplied"), o.clocks.applied)
                          : library.tr("clocksOK"),
                      action: library.tr(o.clocks.pending > 0 ? "check" : "showCard"), prominent: o.clocks.pending > 0) {
            library.sheet = .clocks
        }
        AssistantCard(icon: "square.stack.3d.up", tint: .blue, title: library.tr("cardMoments"), done: library.isDone("duplicates"),
                      text: momentsText(o.moments),
                      action: o.moments.total == 0 ? nil : library.tr(o.moments.needYou > 0 ? "review" : "showCard"),
                      prominent: o.moments.needYou > 0) {
            library.reviewedMoments = []          // a fresh look shows every moment again
            library.sheet = .moments
        }
        AssistantCard(icon: "camera.aperture", tint: .orange, title: library.tr("cardBlurry"), done: library.isDone("blurry"),
                      text: o.blurry.total == 0 ? library.tr("blurryNone")
                          : String(format: library.tr("blurrySome"), Strings.count(o.blurry.total, .photo, library.lang), o.blurry.leftOut),
                      action: o.blurry.total == 0 ? nil : library.tr("review"), prominent: false) {
            library.destination = .blurry
        }
    }

    @ViewBuilder func restCards(_ o: Overview, _ s: [String: Bool], busy: Bool) -> some View {
        AssistantCard(icon: "calendar", tint: .purple, title: library.tr("cardEvents"), done: s["events"] == true,
                      text: String(format: library.tr("eventsText"), Strings.count(o.events.events, .event, library.lang), Strings.count(o.events.days, .day, library.lang)),
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
                      text: o.export.done ? library.tr("exportDone") : String(format: library.tr("exportReady"), Strings.count(o.export.photos, .photo, library.lang)),
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
