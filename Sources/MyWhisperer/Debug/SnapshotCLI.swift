import AppKit
import MyWhispererCore
import SwiftUI

/// `myWhisperer --snapshot <screen|all> <out.png|out-dir> [--dark]`
///
/// Renders a screen offscreen with sample data and writes a PNG, so the UI can
/// be reviewed without clicking through the app (no Screen Recording needed).
@MainActor
enum SnapshotCLI {
    static let screens: [String] =
        OnboardingStep.allCases.map { "onboarding-\($0.title.lowercased().replacingOccurrences(of: " ", with: ""))" }
        + Pane.allCases.map { "main-\($0.rawValue)" }
        + ["hud-recording", "hud-command", "hud-handsfree", "hud-processing", "hud-done", "hud-copied", "hud-nothing", "hud-error"]

    static func run(_ arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 2 else {
            print("usage: myWhisperer --snapshot <screen|all> <out.png|dir> [--dark]\nscreens: \(screens.joined(separator: ", "))")
            return 2
        }
        let screen = arguments[index + 1]
        let output = URL(fileURLWithPath: arguments[index + 2])
        let dark = arguments.contains("--dark")

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        if screen == "all" {
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for name in screens {
                let file = output.appendingPathComponent("\(name)\(dark ? "-dark" : "").png")
                guard render(name, to: file, dark: dark) else { return 1 }
                print(file.path)
            }
            return 0
        }
        guard screens.contains(screen) else {
            print("unknown screen \(screen)")
            return 2
        }
        return render(screen, to: output, dark: dark) ? 0 : 1
    }

    private static func render(_ screen: String, to url: URL, dark: Bool) -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myWhispererSnapshot-\(UUID().uuidString)")
        let model = AppModel(directory: directory, readKeychain: false, persistHistory: false)
        model.applyPreviewState()

        let (view, size, isHUD) = makeView(screen, model: model)
        let hosting = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, dark ? .dark : .light)))
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size),
                              styleMask: isHUD ? [.borderless] : [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        if isHUD {
            window.isOpaque = false
            window.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        }
        window.orderFrontRegardless()

        // Let SwiftUI lay out, run onAppear, and settle animations.
        if screen.hasPrefix("hud-recording") || screen == "hud-command" || screen == "hud-handsfree" {
            for i in 0..<14 {
                model.audioLevel = Float(0.3 + 0.55 * abs(sin(Double(i) * 0.7)))
                RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        hosting.layoutSubtreeIfNeeded()
        hosting.display()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: directory)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            print("write failed: \(error)")
            return false
        }
    }

    private static func makeView(_ screen: String, model: AppModel) -> (any View, NSSize, Bool) {
        if screen.hasPrefix("onboarding-") {
            let name = String(screen.dropFirst("onboarding-".count))
            let step = OnboardingStep.allCases.first { $0.title.lowercased().replacingOccurrences(of: " ", with: "") == name } ?? .welcome
            if step == .permissions {
                model.permissions = PermissionsSnapshot(microphone: .granted, accessibility: .denied, inputMonitoring: .notDetermined)
            }
            if step == .keys {
                model.removePreviewKey(.anthropic)
                model.removePreviewKey(.openAI)
                model.keyStates[.openAI] = .invalid("Your OpenAI API key was rejected.")
            }
            return (OnboardingView(model: model, initialStep: step) {}, NSSize(width: 760, height: 560), false)
        }
        if screen.hasPrefix("main-"), let pane = Pane(rawValue: String(screen.dropFirst("main-".count))) {
            let navigation = Navigation()
            navigation.pane = pane
            if pane == .audio { model.audioLevel = 0.55 }
            return (MainView(model: model, navigation: navigation), NSSize(width: 980, height: 700), false)
        }
        let phase: DictationPhase = switch screen {
        case "hud-command": .recording(mode: .command, handsFree: false)
        case "hud-handsfree": .recording(mode: .dictate, handsFree: true)
        case "hud-processing": .processing(mode: .dictate)
        case "hud-done": .done(copied: false)
        case "hud-copied": .done(copied: true)
        case "hud-nothing": .nothingHeard
        case "hud-error": .error(message: "Add an API key", action: .openAPIKeys)
        default: .recording(mode: .dictate, handsFree: false)
        }
        model.previewPhase(phase)
        return (HUDView(model: model), HUDController.size, true)
    }
}
