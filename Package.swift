// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyWhisperer",
    platforms: [.macOS(.v14)],
    targets: [
        // App shell: AppKit/SwiftUI adapters, windows, system integration.
        // Swift 5 mode: event-tap and Accessibility C callbacks fight strict
        // concurrency checking, and the core logic lives in MyWhispererCore.
        .executableTarget(
            name: "MyWhisperer",
            dependencies: ["MyWhispererCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // UI-free logic (prompts, providers, stores, dictation state machine)
        // so it can be unit tested.
        .target(name: "MyWhispererCore"),
        .testTarget(
            name: "MyWhispererCoreTests",
            dependencies: ["MyWhispererCore"]
        ),
    ]
)
