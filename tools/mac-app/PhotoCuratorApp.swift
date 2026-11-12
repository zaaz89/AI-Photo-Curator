// Photo Curator: a native Mac window around the local app.
//
// The app starts the Python server from the project folder (bound to 127.0.0.1 only),
// waits until it answers, and shows it in a WKWebView. Quitting the app stops the
// server it started. If a server is already running on the port, the window uses it
// and leaves it running on quit. Nothing is loaded from the internet: navigation
// outside 127.0.0.1 is refused.
//
// Built by scripts/build-mac-app.sh, which writes the project path into Info.plist
// (key PCProjectPath).

import AppKit
import WebKit

let port = 5014
let home = URL(string: "http://127.0.0.1:\(port)/")!
let titleBarHeight: CGFloat = 28

/// Transparent strip along the top of the window: the title bar area is drawn by the
/// web page (full-size content), so this strip keeps the window draggable there.
final class DragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var server: Process?
    var spinner: NSProgressIndicator!
    var message: NSTextField!

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        buildWindow()
        if serverAnswers() {
            web.load(URLRequest(url: home))
        } else {
            startServer()
            waitForServer(tries: 0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ note: Notification) {
        guard let p = server, p.isRunning else { return }
        p.terminate()                                   // SIGTERM: the server stops its jobs
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    // MARK: window

    func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1320, height: 860)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Photo Curator"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("PhotoCuratorMain")
        if !window.setFrameUsingName("PhotoCuratorMain") { window.center() }
        window.delegate = self

        let cfg = WKWebViewConfiguration()
        // Tell the page it runs inside the Mac window (leaves room for the window buttons).
        cfg.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('macapp')", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        cfg.websiteDataStore = .default()
        web = WKWebView(frame: frame, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.setValue(false, forKey: "drawsBackground")      // window background shows while loading
        web.autoresizingMask = [.width, .height]

        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(web)
        let strip = DragStrip(frame: NSRect(x: 0, y: frame.height - titleBarHeight, width: frame.width, height: titleBarHeight))
        strip.autoresizingMask = [.width, .minYMargin]

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)
        message = NSTextField(labelWithString: "Starting Photo Curator…")
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)
        container.addSubview(message)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -12),
            message.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            message.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -80),
        ])
        container.addSubview(strip)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showLoading(_ on: Bool, _ text: String? = nil) {
        spinner.isHidden = !on
        message.isHidden = text == nil && !on
        if let text = text { message.stringValue = text }
    }

    // MARK: server

    func projectPath() -> String? {
        if let p = Bundle.main.object(forInfoDictionaryKey: "PCProjectPath") as? String,
           FileManager.default.fileExists(atPath: p + "/photo_curator.py") { return p }
        return nil
    }

    func uvPath() -> String? {
        let candidates = [NSHomeDirectory() + "/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func startServer() {
        guard let project = projectPath() else {
            return fail("The project folder was not found. Build the app again with scripts/build-mac-app.sh.")
        }
        let logDir = URL(fileURLWithPath: project).appendingPathComponent("local-data/logs")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logURL = logDir.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)

        let p = Process()
        p.currentDirectoryURL = URL(fileURLWithPath: project)
        let venvPython = project + "/.venv/bin/python"
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            p.executableURL = URL(fileURLWithPath: venvPython)
            p.arguments = ["photo_curator.py"]
        } else if let uv = uvPath() {
            p.executableURL = URL(fileURLWithPath: uv)
            p.arguments = ["run", "python", "photo_curator.py"]
        } else {
            return fail("Python environment not found. In the project folder run: uv sync")
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        p.standardOutput = log
        p.standardError = log
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self, self.server === proc else { return }
                self.server = nil
                if !NSApp.isRunning { return }
                self.fail("The app's engine stopped (exit \(proc.terminationStatus)). Details: local-data/logs/server.log")
            }
        }
        do { try p.run(); server = p } catch { fail("Could not start the engine: \(error.localizedDescription)") }
    }

    func serverAnswers() -> Bool {
        var req = URLRequest(url: home.appendingPathComponent("api/settings"))
        req.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        return ok
    }

    func waitForServer(tries: Int) {
        if tries > 120 { return fail("The engine did not start within a minute. Details: local-data/logs/server.log") }
        DispatchQueue.global().async {
            let ok = self.serverAnswers()
            DispatchQueue.main.async {
                if ok { self.web.load(URLRequest(url: home)) }
                else if self.server != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.waitForServer(tries: tries + 1) } }
            }
        }
    }

    func fail(_ text: String) {
        showLoading(false, text)
        spinner.isHidden = true
        web.isHidden = true
    }

    // MARK: web view

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showLoading(false)
        web.isHidden = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.host == "127.0.0.1" && url.port == port { return decisionHandler(.allow) }
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return decisionHandler(.allow) }
        decisionHandler(.cancel)                               // nothing leaves this Mac from the window
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK")
        a.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert(); a.messageText = prompt; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    // MARK: menu

    @objc func reloadPage(_ sender: Any?) { web.reload() }
    @objc func openLog(_ sender: Any?) {
        guard let p = projectPath() else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: p + "/local-data/logs/server.log"))
    }
    @objc func zoomIn(_ sender: Any?) { web.pageZoom = min(2.0, web.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { web.pageZoom = max(0.6, web.pageZoom - 0.1) }
    @objc func zoomReset(_ sender: Any?) { web.pageZoom = 1.0 }

    func buildMenu() {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.keyEquivalentModifierMask = mods; return i
        }
        let appMenu = NSMenu()
        appMenu.addItem(item("About Photo Curator", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Photo Curator", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Photo Curator", #selector(NSApplication.terminate(_:)), "q"))

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        let view = NSMenu(title: "View")
        view.addItem(item("Reload", #selector(reloadPage(_:)), "r"))
        view.addItem(.separator())
        view.addItem(item("Actual Size", #selector(zoomReset(_:)), "0"))
        view.addItem(item("Zoom In", #selector(zoomIn(_:)), "+"))
        view.addItem(item("Zoom Out", #selector(zoomOut(_:)), "-"))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let win = NSMenu(title: "Window")
        win.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        win.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), ""))
        win.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))

        let help = NSMenu(title: "Help")
        help.addItem(item("Show Engine Log", #selector(openLog(_:)), ""))

        for (title, menu) in [("Photo Curator", appMenu), ("Edit", edit), ("View", view), ("Window", win), ("Help", help)] {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: ""); top.submenu = menu; main.addItem(top)
        }
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
        NSApp.helpMenu = help
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
