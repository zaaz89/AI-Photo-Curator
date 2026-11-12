import AppKit
import CuratorCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onQuit: (() -> Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { onQuit?() }
}

@main
struct PhotoCuratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine: EngineController
    @StateObject private var library: LibraryModel

    init() {
        let api = APIClient()
        _engine = StateObject(wrappedValue: EngineController(api: api))
        _library = StateObject(wrappedValue: LibraryModel(api: api))
    }

    var body: some Scene {
        // One main window: the engine and the model belong to it.
        Window("Photo Curator", id: "main") {
            RootView()
                .environmentObject(engine)
                .environmentObject(library)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    delegate.onQuit = { [engine] in MainActor.assumeIsolated { engine.stopIfOwned() } }
                    if engine.state != .ready { engine.start() }
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(library: library, engine: engine) }

        Window(library.tr("classicView"), id: "classic") {
            ClassicWebView(url: URL(string: "http://127.0.0.1:5014/")!)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1300, height: 860)

        Settings { SettingsView().environmentObject(library) }
    }
}

struct AppCommands: Commands {
    @ObservedObject var library: LibraryModel
    @ObservedObject var engine: EngineController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(library.tr("photoMenu")) {
            // F, X and B work in the photo grid (see PhotoGrid); here they are listed for the menu.
            Button(library.tr("favourite") + "  (F)") { library.toggleFavourite() }
            Button(library.tr("leaveOut") + "  (X)") { library.toggleLeaveOut() }
            Button(library.tr("wallpaper") + "  (B)") { library.toggleWallpaper() }
            Divider()
            Button(library.tr("quickLook")) { library.toggleQuickLook() }
                .keyboardShortcut("y", modifiers: .command)
            Divider()
            Button(library.tr("analyseAgain")) { library.analyse() }.disabled(library.job.running)
            Button(library.tr("stop")) { library.stopJob() }.disabled(!library.job.running)
        }
        CommandGroup(after: .textEditing) {
            Button(library.tr("find")) { library.searchFocusRequest += 1 }.keyboardShortcut("f")
        }
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button(library.tr("classicView")) { openWindow(id: "classic") }.keyboardShortcut("k", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button(library.tr("showLog")) { engine.openLog() }
        }
    }
}

/// Engine starting / failed / ready.
struct RootView: View {
    @EnvironmentObject var engine: EngineController
    @EnvironmentObject var library: LibraryModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        switch engine.state {
        case .ready:
            MainWindow()
                .task { library.undoManager = undoManager; await library.start() }
                .onChange(of: undoManager) { _, um in library.undoManager = um }
        case .starting:
            VStack(spacing: 18) {
                AIRing(symbol: "sparkles", size: 72, spinning: true)
                Text(library.tr("starting")).font(.title3.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("\(Int(ctx.date.timeIntervalSince(engine.startedAt))) s").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let why):
            ContentUnavailableView {
                Label(library.tr("engineFailed"), systemImage: "bolt.horizontal.circle")
            } description: { Text(why) } actions: {
                Button(library.tr("tryAgain")) { engine.start() }.buttonStyle(.glassProminent)
                Button(library.tr("showLog")) { engine.openLog() }
            }
        }
    }
}
