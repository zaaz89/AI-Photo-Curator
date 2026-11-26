import AppKit
import CuratorCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onQuit: (() -> Void)?
    /// True while an album is being sorted (M14a): closing the window then keeps the app and the engine working
    /// ("You can close the window; I keep working"); the app quits by itself when the sorting ends.
    var keepWorking: (() -> Bool)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !(keepWorking?() ?? false) }
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
                    delegate.keepWorking = { [library] in MainActor.assumeIsolated { library.analysing } }
                    if engine.state != .ready { engine.start() }
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: ["photocurator"])     // the background channel goes to this window, never a new one
        .commands { AppCommands(library: library, engine: engine) }

        Window(library.tr("classicView"), id: "classic") {
            ClassicWebView(url: URL(string: "http://127.0.0.1:5014/")!)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1300, height: 860)
        .keyboardShortcut("k", modifiers: [.command, .shift])     // the system lists the window in the Window menu

        Settings { SettingsView().environmentObject(library) }
    }
}

struct AppCommands: Commands {
    @ObservedObject var library: LibraryModel
    @ObservedObject var engine: EngineController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(library.tr("newAlbumButton")) { library.newAlbum() }.keyboardShortcut("n")
        }
        CommandMenu(library.tr("albumMenu")) {
            // The path's stations (M14a): ⌘1 … ⌘4. A station ahead of the album opens the current one.
            ForEach(JourneyStation.allCases) { s in
                Button(s.title(library.lang)) { library.open(station: s) }
                    .keyboardShortcut(KeyEquivalent(Character(String(s.menuDigit))))
                    .disabled(library.trips.isEmpty)
            }
            Divider()
            Button(library.tr("journeyPrimaryMenu") + ": " + library.journey.actionTitle(library.lang)) { library.performPrimary() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(library.trips.isEmpty || !library.journey.action.isEnabled || library.reviewFilter != nil)
            Button(library.tr("addFolderMenu")) { library.chooseFolders() }
                .disabled(library.shownTrip == nil)
            Divider()
            Button(library.tr("allPhotos")) { go(.all) }.disabled(library.trips.isEmpty)
            Button(library.tr("leftOut")) { go(.leftOut) }.keyboardShortcut("l").disabled(library.trips.isEmpty)
            Button(library.tr("viewMoments")) { go(.moments) }.disabled(library.trips.isEmpty)
            Button(library.tr("viewChapters")) { go(.chapters) }.disabled(library.trips.isEmpty)
            Button(library.tr("step_photos")) { go(.people) }.disabled(library.trips.isEmpty)
            Divider()
            Button(library.tr("quickReview")) { library.startReview() }.keyboardShortcut("r")
            Button(library.tr("quickReviewEverything")) { library.startReview(.all) }.keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button(library.tr("analyseAgain")) { library.analyse() }.disabled(library.job.running || library.shownTrip == nil)
            Button(library.tr("stop")) { library.stopJob() }.disabled(!library.job.running)
            Divider()
            Button(library.tr("removeAlbumMenu")) { library.removeAlbumRequest = library.tripId }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(library.tripId == nil || (library.job.running && library.job.collection == library.tripId))
        }
        CommandMenu(library.tr("photoMenu")) {
            // K, X, F, B and Space work in the photo grid (see PhotoGrid); here they are listed for the menu.
            // K / X are the grid's keep / leave out, the same family as → / ← in the quick review (M12e, #18).
            Button(library.tr("keepInAlbum") + "  (K)") { library.keepTargets() }
            Button(library.tr("leaveOut") + "  (X)") { library.leaveOutTargets() }
            Button(library.tr("favourite") + "  (F)") { library.toggleFavourite() }
            Button(library.tr("wallpaper") + "  (B)") { library.toggleWallpaper() }
            Divider()
            Button(library.tr("quickLook") + "  (Space)") { library.toggleQuickLook() }
                .keyboardShortcut("y", modifiers: .command)
        }
        CommandGroup(replacing: .undoRedo) {
            // In the quick review ⌘Z is Back: it shows the photo again and undoes its decision.
            // Otherwise Undo and Redo go through the responder chain as usual, so a text field, a sheet or the
            // Classic window undoes its own change, never the main window's last mark by mistake.
            Button(library.reviewFilter != nil ? library.tr("back") : library.tr("undo")) {
                if library.reviewFilter != nil { library.reviewUndoRequest += 1 }
                else { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
            }
            .keyboardShortcut("z")
            Button(library.tr("redo")) { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(library.reviewFilter != nil)
        }
        CommandGroup(after: .textEditing) {
            Button(library.tr("find")) { library.searchFocusRequest += 1 }.keyboardShortcut("f")
        }
        CommandGroup(replacing: .help) {
            Button(library.tr("showLog")) { engine.openLog() }
        }
    }
}

@MainActor extension AppCommands {
    func go(_ d: Destination) {
        library.reviewFilter = nil
        library.destination = d
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
                .onOpenURL { library.handleAutomation($0) }
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
            // Localised (the language is remembered from the last run), the raw reason behind Details (M12e, #8).
            let h = why.human(library.lang)
            ContentUnavailableView {
                Label(library.tr("engineFailed"), systemImage: "bolt.horizontal.circle")
            } description: {
                VStack(spacing: Space.m) {
                    Text(h.message)
                    DisclosureGroup(library.tr("details")) {
                        Text(h.details).font(TypeRole.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 420)
                }
            } actions: {
                Button(library.tr("tryAgain")) { engine.start() }.buttonStyle(.glassProminent)
                Button(library.tr("showLog")) { engine.openLog() }
            }
            .task(id: h) { AccessibilityNotification.Announcement(library.tr("engineFailed") + ". " + h.message).post() }
        }
    }
}
