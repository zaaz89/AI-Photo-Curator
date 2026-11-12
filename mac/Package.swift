// swift-tools-version: 6.2
// Photo Curator native app (M8). Build: ../scripts/build-mac-app.sh   Tests: ../scripts/test-mac.sh
import PackageDescription

let package = Package(
    name: "PhotoCurator",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    targets: [
        // Models, API client, library logic and strings. No SwiftUI, so it is fully unit-tested.
        .target(name: "CuratorCore"),
        // The SwiftUI app.
        .executableTarget(name: "PhotoCurator", dependencies: ["CuratorCore"]),
        .testTarget(name: "CuratorCoreTests", dependencies: ["CuratorCore"], resources: [.copy("Fixtures")]),
        // The app's model (selection, marks, undo, engine start) against a stubbed engine.
        .testTarget(name: "PhotoCuratorTests", dependencies: ["PhotoCurator", "CuratorCore"], resources: [.copy("Fixtures")]),
    ]
)
