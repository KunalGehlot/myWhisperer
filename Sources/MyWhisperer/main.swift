import AppKit

// Developer entry points (see AGENTS.md → "Seeing and driving the app").
let arguments = CommandLine.arguments
if arguments.contains("--snapshot") {
    exit(MainActor.assumeIsolated { SnapshotCLI.run(arguments) })
}
if arguments.contains("--dictate-file") {
    exit(PipelineCLI.run(arguments))
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
