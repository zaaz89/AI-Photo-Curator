import AppKit
import CuratorCore
import Foundation

/// Starts the Python engine from the project folder (path in Info.plist, key PCProjectPath),
/// waits until it answers, and stops it on quit if this app started it. An engine that
/// was already running is used and left running.
@MainActor final class EngineController: ObservableObject {
    enum State: Equatable { case starting, ready, failed(String) }
    @Published private(set) var state: State = .starting
    @Published private(set) var startedAt = Date()
    private var process: Process?
    let api: APIClient

    init(api: APIClient) { self.api = api }

    var projectPath: String? {
        let p = Bundle.main.object(forInfoDictionaryKey: "PCProjectPath") as? String
            ?? ProcessInfo.processInfo.environment["PC_PROJECT_PATH"]
        guard let p, FileManager.default.fileExists(atPath: p + "/photo_curator.py") else { return nil }
        return p
    }

    func start() {
        startedAt = Date()
        state = .starting
        Task {
            if await api.ping() { state = .ready; return }
            do { try launch() } catch { state = .failed(error.localizedDescription); return }
            for _ in 0..<180 {                                    // up to 90 s (cold start is ~25 s)
                if await api.ping() { state = .ready; return }
                if let p = process, !p.isRunning { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            state = .failed("The engine did not start. Details: local-data/logs/server.log")
        }
    }

    private func launch() throws {
        guard let project = projectPath else {
            throw NSError(domain: "PhotoCurator", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Project folder not found. Rebuild the app with scripts/build-mac-app.sh."])
        }
        let logDir = URL(fileURLWithPath: project).appendingPathComponent("local-data/logs")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logURL = logDir.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        let p = Process()
        p.currentDirectoryURL = URL(fileURLWithPath: project)
        let venv = project + "/.venv/bin/python"
        let uv = [NSHomeDirectory() + "/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        if FileManager.default.isExecutableFile(atPath: venv) {
            p.executableURL = URL(fileURLWithPath: venv); p.arguments = ["photo_curator.py"]
        } else if let uv {
            p.executableURL = URL(fileURLWithPath: uv); p.arguments = ["run", "python", "photo_curator.py"]
        } else {
            throw NSError(domain: "PhotoCurator", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Python environment not found. In the project folder run: uv sync"])
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        p.standardOutput = log
        p.standardError = log
        try p.run()
        process = p
    }

    /// Called on quit: stop the engine only if this app started it.
    func stopIfOwned() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        process = nil
    }

    func openLog() {
        guard let p = projectPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: p + "/local-data/logs/server.log"))
    }
}
