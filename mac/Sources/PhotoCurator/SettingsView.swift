import CuratorCore
import SwiftUI

/// Settings (M11): a page in the main window (sidebar, album home) and the same page in the Settings window (⌘,).
/// Every setting says in one sentence what it changes. Values live in the engine's settings file on this Mac.
struct SettingsPage: View {
    @EnvironmentObject var library: LibraryModel
    @State private var share: Double?                    // the slider while it moves; saved when it is let go
    @State private var weights: [String: Double] = [:]
    static let weightKeys = ["faces", "focus", "look", "resolution"]

    var body: some View {
        Form {
            speed
            quality
            keeper
            Section {
                Picker(library.tr("language"), selection: binding(\.uiLanguage, key: "ui_language")) {
                    Text("English").tag("en")
                    Text("Slovenščina").tag("sl")
                }
            } footer: {
                Text(library.tr("aiLimitHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .task { await library.loadSettings() }
    }

    // MARK: speed

    var currentShare: Int { Int(share ?? Double(library.settings?.aiGpuShare ?? EngineSettings.fallback.aiGpuShare)) }

    var speed: some View {
        Section {
            LabeledContent(library.tr("gpuShare")) {
                HStack(spacing: 12) {
                    Slider(value: Binding(get: { Double(currentShare) }, set: { share = $0 }),
                           in: Double(EngineSettings.gpuShareRange.lowerBound)...Double(EngineSettings.gpuShareRange.upperBound),
                           step: 5) { editing in if !editing { saveShare() } }
                        .frame(minWidth: 180)
                        .accessibilityValue(String(format: library.tr("gpuShareValue"), currentShare))
                    Text(String(format: library.tr("gpuShareValue"), currentShare))
                        .monospacedDigit().frame(minWidth: 92, alignment: .trailing)
                        .contentTransition(.numericText(value: Double(currentShare)))
                }
            }
            Text(library.tr("gpuHint")).font(.callout).foregroundStyle(.secondary)
            Label(estimate, systemImage: "clock").font(.callout)
                .contentTransition(.numericText())
                .motionAnimation(.quick, value: currentShare)
            Toggle(isOn: binding(\.aiPauseOnBattery, key: "ai_pause_on_battery")) {
                Text(library.tr("pauseOnBattery"))
                Text(library.tr("batteryHint"))
            }
        } header: {
            Text(library.tr("settingsSpeed"))
        } footer: {
            Text(library.tr("thermalNote")).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// How long a first analysis takes at the slider's value, from the speed measured on this Mac.
    var estimate: String {
        guard let sp = library.speed else { return library.tr("estimateLater") }
        let l = library.lang
        if library.tripId != nil, let f = library.overview?.facts, f.photos - f.videos > 0 {
            let n = f.photos - f.videos
            guard let now = sp.seconds(photos: n, share: currentShare), let full = sp.seconds(photos: n, share: 100) else {
                return library.tr("estimateLater")
            }
            return String(format: library.tr("estimateAlbum"), Strings.photos(n, l),
                          Strings.duration(now, l), Strings.duration(full, l))
        }
        guard let now = sp.seconds(photos: 200, share: currentShare), let full = sp.seconds(photos: 200, share: 100) else {
            return library.tr("estimateLater")
        }
        return String(format: library.tr("estimateNoAlbum"), Strings.duration(now, l), Strings.duration(full, l))
    }

    func saveShare() {
        guard let v = share else { return }
        library.settings?.aiGpuShare = Int(v)
        library.save(["ai_gpu_share": Int(v)])
        share = nil
    }

    // MARK: quality

    var level: String { library.settings?.qualityStrictness ?? "normal" }

    var quality: some View {
        Section {
            Picker(library.tr("strictness"), selection: Binding(get: { level }, set: { library.setStrictness($0) })) {
                ForEach(EngineSettings.strictnessLevels, id: \.self) { Text(library.tr("strict_" + $0)).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(library.tr("strictText_" + level)).font(.callout).foregroundStyle(.secondary)
                .motionAnimation(.quick, value: level)
            if library.tripId != nil && !library.photos.isEmpty {
                Label(String(format: library.tr("strictNow"), library.count(.blurry)), systemImage: "camera.aperture")
                    .font(.callout)
                    .contentTransition(.numericText(value: Double(library.count(.blurry))))
                    .motionAnimation(.quick, value: library.count(.blurry))
            }
        } header: {
            Text(library.tr("settingsQuality"))
        } footer: {
            Text(library.tr("strictApplies")).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: best of each moment

    var keeper: some View {
        Section {
            ForEach(Self.weightKeys, id: \.self) { k in
                LabeledContent(library.tr("w_" + k)) {
                    HStack {
                        Slider(value: Binding(get: { weights[k] ?? Double(library.settings?.keeperWeights[k] ?? 0) },
                                              set: { weights[k] = $0 }),
                               in: 0...100, step: 5) { editing in if !editing { saveWeights() } }
                        Text("\(Int(weights[k] ?? Double(library.settings?.keeperWeights[k] ?? 0)))")
                            .monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                }
            }
        } header: {
            Text(library.tr("bestOfMoment"))
        } footer: {
            Text(library.tr("keeperHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    func saveWeights() {
        var w = library.settings?.keeperWeights ?? [:]
        for (k, v) in weights { w[k] = Int(v) }
        library.save(["keeper_weights": w])
    }

    func binding<T>(_ path: WritableKeyPath<EngineSettings, T>, key: String) -> Binding<T> where T: Hashable {
        Binding(
            get: { library.settings?[keyPath: path] ?? EngineSettings.fallback[keyPath: path] },
            set: { v in library.settings?[keyPath: path] = v; library.save([key: v]) })
    }
}

/// The Settings window (⌘,) shows the same page.
struct SettingsView: View {
    var body: some View {
        SettingsPage().frame(width: 620, height: 720)
    }
}

/// One line on the album home: what the analysis may use and how strict the quality check is, with a way to change it.
struct SettingsStrip: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
            Text(String(format: library.tr("settingsSummary"), library.settings?.aiGpuShare ?? EngineSettings.fallback.aiGpuShare,
                        library.tr("strict_" + (library.settings?.qualityStrictness ?? "normal")).lowercased()))
                .foregroundStyle(.secondary)
            Spacer()
            Button(library.tr("settingsChange")) { withMotion(.settle) { library.destination = .settings } }
                .buttonStyle(.link)
        }
        .font(.callout)
        .task { if library.settings == nil { await library.loadSettings() } }
    }
}

extension EngineSettings {
    static let fallback = EngineSettings(uiLanguage: "en", aiGpuShare: 30, aiPauseOnBattery: false,
                                         keeperWeights: ["faces": 40, "focus": 30, "look": 20, "resolution": 10])
}
