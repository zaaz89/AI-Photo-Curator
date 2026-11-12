import CuratorCore
import SwiftUI

/// The AI colours used for everything that shows the app at work.
let aiGradientColors: [Color] = [
    Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.38, blue: 1.0),
    Color(red: 1.0, green: 0.35, blue: 0.62), Color(red: 1.0, green: 0.62, blue: 0.25),
    Color(red: 0.25, green: 0.55, blue: 1.0),
]

/// A rotating gradient ring around a symbol. Static when Reduce Motion is on or nothing runs.
struct AIRing: View {
    let symbol: String
    var size: CGFloat = 22
    var spinning = true
    var progress: Double? = nil                      // 0…1 draws a progress arc over the ring
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let line = max(2, size / 9)
        ZStack {
            if spinning && !reduceMotion {
                TimelineView(.animation) { ctx in
                    ring(angle: .degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360), line: line)
                }
            } else {
                ring(angle: .zero, line: line)
            }
            if let progress {
                Circle().trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(.primary.opacity(0.85), style: StrokeStyle(lineWidth: line * 0.55, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(line * 0.2)
                    .animation(.easeOut(duration: 0.4), value: progress)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating, isActive: spinning && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    func ring(angle: Angle, line: CGFloat) -> some View {
        Circle()
            .strokeBorder(AngularGradient(colors: aiGradientColors, center: .center, angle: angle), lineWidth: line)
            .shadow(color: aiGradientColors[1].opacity(spinning ? 0.6 : 0), radius: line * 1.5)
    }
}

/// Toolbar capsule: what the engine is doing right now, with a live percentage. Click for details.
struct ActivityPill: View {
    @EnvironmentObject var library: LibraryModel
    @State private var showDetails = false

    var body: some View {
        let job = library.job, phase = job.phase
        Button { showDetails.toggle() } label: {
            HStack(spacing: 8) {
                AIRing(symbol: phase.symbol, size: 22, spinning: job.running, progress: job.running ? job.progress / 100 : nil)
                if job.running || phase == .failed {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(library.tr("phase_" + phase.rawValue)).font(.callout.weight(.semibold)).lineLimit(1)
                        if let c = job.counter {
                            Text("\(c.done) / \(c.total)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                .contentTransition(.numericText(value: Double(c.done)))
                        }
                    }
                    if job.running {
                        Text("\(Int(job.progress))%").font(.callout.weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText(value: job.progress))
                            .animation(.snappy, value: job.progress)
                    }
                }
            }
            .padding(.horizontal, job.running ? 6 : 0)
        }
        .help(job.running ? job.status : library.tr("phase_idle"))
        .accessibilityLabel(job.running ? "\(library.tr("phase_" + phase.rawValue)), \(Int(job.progress))%" : library.tr("phase_idle"))
        .popover(isPresented: $showDetails, arrowEdge: .bottom) { ActivityDetails() }
        .animation(.spring(duration: 0.4), value: job.running)
    }
}

struct ActivityDetails: View {
    @EnvironmentObject var library: LibraryModel
    static let analysisPhases: [ActivityPhase] = [.reading, .clocks, .duplicates, .quality, .faces, .videos, .searchIndex]

    var body: some View {
        let job = library.job, current = job.phase
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AIRing(symbol: current.symbol, size: 40, spinning: job.running, progress: job.running ? job.progress / 100 : nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.tr(job.running ? "working" : (current == .failed ? "phase_failed" : "phase_idle"))).font(.headline)
                    Text(job.status.isEmpty ? library.tr("nothingRunning") : job.status)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            if job.running, let i = Self.analysisPhases.firstIndex(of: current) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Self.analysisPhases.enumerated()), id: \.offset) { k, ph in
                        HStack(spacing: 8) {
                            Image(systemName: k < i ? "checkmark.circle.fill" : (k == i ? ph.symbol : "circle"))
                                .foregroundStyle(k < i ? AnyShapeStyle(.green) : (k == i ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary)))
                                .frame(width: 18)
                            Text(library.tr("phase_" + ph.rawValue)).foregroundStyle(k > i ? .secondary : .primary)
                        }
                        .font(.callout)
                    }
                }
            }
            HStack {
                Spacer()
                if job.running {
                    Button(library.tr("stop"), role: .destructive) { library.stopJob() }
                } else {
                    Button(library.tr("analyseAgain")) { library.analyse() }.buttonStyle(.glassProminent)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// A soft gradient glow along the window edge while local AI runs on this Mac.
struct AIGlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active {
                Group {
                    if reduceMotion {
                        glow(.zero)
                    } else {
                        TimelineView(.animation) { ctx in
                            glow(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: active)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    func glow(_ angle: Angle) -> some View {
        let gradient = AngularGradient(colors: aiGradientColors, center: .center, angle: angle)
        return ZStack {
            RoundedRectangle(cornerRadius: 16).strokeBorder(gradient, lineWidth: 14).blur(radius: 18).opacity(0.9)
            RoundedRectangle(cornerRadius: 16).strokeBorder(gradient, lineWidth: 2).opacity(0.7)
        }
    }
}
