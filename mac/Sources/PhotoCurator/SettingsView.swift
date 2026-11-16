import CuratorCore
import SwiftUI

/// Settings window (⌘,). Values live in the engine's settings file on this Mac.
struct SettingsView: View {
    @EnvironmentObject var library: LibraryModel
    @State private var weights: [String: Double] = [:]
    static let weightKeys = ["faces", "focus", "look", "resolution"]

    var body: some View {
        TabView {
            Tab(library.tr("general"), systemImage: "gearshape") { general }
            Tab(library.tr("bestOfMoment"), systemImage: "square.stack.3d.up") { keeper }
        }
        .frame(width: 520)
        .task { if library.settings == nil { library.settings = try? await library.api.settings() } }
    }

    var general: some View {
        Form {
            Picker(library.tr("language"), selection: binding(\.uiLanguage, key: "ui_language")) {
                Text("English").tag("en")
                Text("Slovenščina").tag("sl")
            }
            Picker(library.tr("aiLimit"), selection: binding(\.aiGpuShare, key: "ai_gpu_share")) {
                Text(library.tr("gentle")).tag(25)
                Text(library.tr("standard")).tag(30)
                Text(library.tr("faster")).tag(50)
                Text(library.tr("noLimit")).tag(100)
            }
            Toggle(library.tr("pauseOnBattery"), isOn: binding(\.aiPauseOnBattery, key: "ai_pause_on_battery"))
            Text(library.tr("aiLimitHint")).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    var keeper: some View {
        Form {
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
            } footer: {
                Text(library.tr("keeperHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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

extension EngineSettings {
    static let fallback = EngineSettings(uiLanguage: "en", aiGpuShare: 30, aiPauseOnBattery: false,
                                         keeperWeights: ["faces": 40, "focus": 30, "look": 20, "resolution": 10])
}
