import AppKit
import Carbon.HIToolbox
import MyWhispererCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var windows = WindowManager(model: model)
    private let recorder = AudioRecorder()
    private let contextCapture = ContextCapture()
    private let inserter = TextInserter()
    private var controller: DictationController!
    private var hotkeys: HotkeyManager!
    private var statusItem: StatusItemController!
    private var hud: HUDController!
    private var router: URLRouter!
    private var pasteShortcut: GlobalShortcut?
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install(openSettings: #selector(openSettingsFromMenu), target: self)
        recorder.deviceUID = model.preferences.inputDeviceUID
        recorder.onLevel = { [weak self] level in self?.model.audioLevel = level }
        inserter.restoreClipboard = { [weak self] in self?.model.preferences.restoreClipboard ?? true }

        controller = DictationController(audio: recorder, contextProvider: contextCapture, inserter: inserter, host: model)
        hud = HUDController(model: model) { [weak self] action in self?.handle(action) }

        model.onPhaseChanged = { [weak self] phase in
            self?.hud.update(for: phase)
            self?.statusItem?.update()
        }
        model.onPreferencesChanged = { [weak self] old in self?.preferencesChanged(from: old) }
        model.openPane = { [weak self] pane in self?.windows.showMain(pane: pane) }
        model.showOnboarding = { [weak self] in self?.windows.showOnboarding() }
        model.insertText = { [weak self] text in await self?.inserter.insert(text) ?? .copiedToClipboard }
        model.micMonitor = { [weak self] on in
            guard let self, !self.controller.phase.isActive else { return }
            if on { try? self.recorder.startMonitoring() } else { self.recorder.stopMonitoring() }
        }

        statusItem = StatusItemController(model: model, actions: .init(
            openPane: { [weak self] pane in self?.windows.showMain(pane: pane) },
            showOnboarding: { [weak self] in self?.windows.showOnboarding() },
            pasteLast: { [weak self] in self?.model.pasteLast() },
            selectDevice: { [weak self] uid in self?.model.preferences.inputDeviceUID = uid }
        ))

        hotkeys = HotkeyManager(hotkey: model.preferences.hotkey, callbacks: .init(
            pressed: { [weak self] mode in
                guard let self, !self.model.isPaused else { return }
                self.controller.hotkeyDown(mode: mode)
            },
            released: { [weak self] in self?.controller.hotkeyUp() },
            modeChanged: { [weak self] mode in self?.controller.switchMode(to: mode) },
            space: { [weak self] in self?.controller.lockHandsFree() ?? false },
            escape: { [weak self] in self?.controller.cancel() ?? false },
            interrupted: { [weak self] in self?.controller.hotkeyInterrupted() },
            isActive: { [weak self] in self?.controller.phase.isActive ?? false }
        ))

        router = URLRouter(model: model, windows: windows, controller: controller, inserter: inserter,
                           contextCapture: contextCapture)
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

        pasteShortcut = GlobalShortcut(keyCode: kVK_ANSI_V, modifiers: cmdKey | controlKey) { [weak self] in
            self?.model.pasteLast()
        }

        model.refreshPermissions()
        model.refreshDevices()
        startHotkeyIfPossible()
        statusItem.update()

        // Permissions can change at any time in System Settings; keep the UI
        // and the hotkey in sync without asking the user to restart.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }

        if !model.preferences.onboardingCompleted {
            windows.showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windows.showMain() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
    }

    // MARK: Private

    private func poll() {
        let wasRunning = model.hotkeyRunning
        model.refreshPermissions()
        if model.permissions.accessibility == .granted {
            if !hotkeys.isRunning { startHotkeyIfPossible() }
        } else if hotkeys.isRunning {
            hotkeys.stop()
            model.hotkeyRunning = false
        }
        if wasRunning != model.hotkeyRunning { statusItem.update() }
    }

    private func startHotkeyIfPossible() {
        guard AXIsProcessTrusted() else {
            model.hotkeyRunning = false
            return
        }
        let started = hotkeys.start()
        model.hotkeyRunning = started
        model.hotkeyNeedsRelaunch = !started
    }

    private func preferencesChanged(from old: Preferences) {
        let prefs = model.preferences
        if prefs.hotkey != old.hotkey { hotkeys.hotkey = prefs.hotkey }
        if prefs.inputDeviceUID != old.inputDeviceUID { recorder.deviceUID = prefs.inputDeviceUID }
        statusItem.update()
    }

    private func handle(_ action: ErrorAction) {
        switch action {
        case .openAPIKeys, .openModels: windows.showMain(pane: .models)
        case .openPermissions: windows.showMain(pane: .privacy)
        }
    }

    @objc private func openSettingsFromMenu() {
        windows.showMain(pane: .general)
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        router.handle(url)
    }
}
