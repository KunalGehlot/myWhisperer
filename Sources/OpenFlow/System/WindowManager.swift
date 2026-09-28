import AppKit
import Observation
import OpenFlowCore
import SwiftUI

/// Which pane the main window shows; set from menus and URLs.
@MainActor
@Observable
final class Navigation {
    var pane: Pane = .home
}

/// Owns the main and onboarding windows. While one is open the app behaves
/// like a regular app (Dock icon, ⌘-Tab); otherwise it lives in the menu bar.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let model: AppModel
    let navigation = Navigation()
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func showMain(pane: Pane? = nil) {
        if let pane { navigation.pane = pane }
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = AppInfo.name
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 780, height: 520)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: MainView(model: model, navigation: navigation))
            window.setFrameAutosaveName("MainWindow")
            if !window.setFrameUsingName("MainWindow") { window.center() }
            window.delegate = self
            mainWindow = window
        }
        present(mainWindow!)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // After a relaunch (e.g. to activate permissions), skip the steps
            // that are already done.
            let initial: OnboardingStep = !model.permissions.requiredGranted ? .welcome
                : model.hasKey(.openAI) && model.hasKey(.anthropic) ? .microphone : .keys
            window.contentViewController = NSHostingController(rootView: OnboardingView(model: model, initialStep: initial) { [weak self] in
                self?.finishOnboarding()
            })
            window.center()
            window.delegate = self
            onboardingWindow = window
        }
        present(onboardingWindow!)
    }

    private func finishOnboarding() {
        model.preferences.onboardingCompleted = true
        onboardingWindow?.close()
        showMain(pane: .home)
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        // Open on the Space the user is looking at, even over full-screen apps.
        window.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === onboardingWindow {
            onboardingWindow = nil
        }
        // Back to a menu-bar-only app once no windows remain.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let visible = [self.mainWindow, self.onboardingWindow].compactMap { $0 }.filter(\.isVisible)
            if visible.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
