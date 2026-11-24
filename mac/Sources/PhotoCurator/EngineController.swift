import AppKit
import CuratorCore
import Foundation

/// Starts the Python engine from the project folder (path in Info.plist, key PCProjectPath),
/// waits until it answers, and stops it on quit if this app started it. An engine that
/// was already running is used and left running.
@MainActor final class EngineController: ObservableObject {
    /// `failed` carries why, as a CuratorCore value the start screen turns into localised text (M12e, #8).
    enum State: Equatable { case starting, ready, failed(EngineStartFailure) }
    @Published private(set) var state: State = .starting
    @Published private(set) var startedAt = Date()
    private var process: Process?
    private let launcher: (@MainActor () throws -> Process)?
    let api: APIClient

    /// `launcher` replaces starting Python (tests).
    init(api: APIClient, launcher: (@MainActor () throws -> Process)? = nil) {
        self.api = api
        self.launcher = launcher
    }

    var projectPath: String? {
        let p = Bundle.main.object(forInfoDictionaryKey: "PCProjectPath") as? String
            ?? ProcessInfo.processInfo.environment["PC_PROJECT_PATH"]
        guard let p, FileManager.default.fileExists(atPath: p + "/photo_curator.py") else { return nil }
        return p
    }

    private var startTask: Task<Void, Never>?

    /// Starts once: a second call while starting (another window, a double click) does nothing,
    /// and a retry first stops the process the previous attempt left behind.
    func start() {
        if startTask != nil { return }
        if let p = process, p.isRunning { stopIfOwned() }
        startedAt = Date()
        state = .starting
        startTask = Task {
            defer { startTask = nil }
            if await api.ping() { state = .ready; return }
            do { if let launcher { process = try launcher() } else { try launch() } }
            catch let f as EngineStartFailure { state = .failed(f); return }
            catch { state = .failed(.launch(error.localizedDescription)); return }
            for _ in 0..<180 {                                    // up to 90 s (cold start is ~25 s)
                if await api.ping() { state = .ready; return }
                if let p = process, !p.isRunning { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            state = .failed(.timeout)
        }
    }

    private func launch() throws {
        guard let project = projectPath else { throw EngineStartFailure.projectMissing }
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
            throw EngineStartFailure.pythonMissing
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
