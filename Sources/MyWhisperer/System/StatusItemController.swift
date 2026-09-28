import AppKit
import MyWhispererCore

/// The menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var openPane: (Pane) -> Void
        var showOnboarding: () -> Void
        var pasteLast: () -> Void
        var selectDevice: (String?) -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let actions: Actions

    init(model: AppModel, actions: Actions) {
        self.model = model
        self.actions = actions
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.setAccessibilityLabel(AppInfo.name)
        update()
    }

    func update() {
        guard let button = item.button else { return }
        let (symbol, tint): (String, NSColor?) = {
            if model.isPaused { return ("waveform.slash", nil) }
            if !model.setupComplete { return ("waveform.badge.exclamationmark", nil) }
            switch model.phase {
            case .recording: return ("waveform", .systemRed)
            case .processing: return ("ellipsis", nil)
            case .error: return ("exclamationmark.triangle", .systemOrange)
            default: return ("waveform", nil)
            }
        }()
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppInfo.name)
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = model.preferences

        let header = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !model.setupComplete {
            menu.addItem(item("Finish setting up…", #selector(finishSetup)))
        }
        menu.addItem(.separator())

        if let last = model.lastDelivered {
            let preview = last.finalText.replacingOccurrences(of: "\n", with: " ")
            let title = preview.count > 48 ? String(preview.prefix(48)) + "…" : preview
            let lastItem = NSMenuItem(title: "“\(title)”", action: nil, keyEquivalent: "")
            lastItem.isEnabled = false
            menu.addItem(lastItem)
            menu.addItem(item("Copy Last Transcript", #selector(copyLast)))
            let paste = item("Paste Last Transcript", #selector(pasteLast))
            paste.keyEquivalent = "v"
            paste.keyEquivalentModifierMask = [.control, .command]
            menu.addItem(paste)
            menu.addItem(.separator())
        }

        // Microphone submenu
        let micMenu = NSMenu()
        let systemDefault = NSMenuItem(title: "System Default", action: #selector(selectDevice(_:)), keyEquivalent: "")
        systemDefault.target = self
        systemDefault.state = prefs.inputDeviceUID == nil ? .on : .off
        micMenu.addItem(systemDefault)
        micMenu.addItem(.separator())
        for device in AudioDevices.inputDevices() {
            let entry = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = device.uid
            entry.state = prefs.inputDeviceUID == device.uid ? .on : .off
            micMenu.addItem(entry)
        }
        let mic = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        mic.submenu = micMenu
        menu.addItem(mic)

        let pause = item(model.isPaused ? "Resume Dictation" : "Pause Dictation", #selector(togglePause))
        menu.addItem(pause)
        menu.addItem(.separator())

        menu.addItem(item("History", #selector(openHistory)))
        menu.addItem(item("Usage: \(model.spentThisMonth.usdString) this month", #selector(openUsage)))
        let settings = item("Open \(AppInfo.name)…", #selector(openHome))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func statusLine() -> String {
        if model.isPaused { return "Paused" }
        if !model.permissions.requiredGranted { return "Needs permissions" }
        if !model.hasKey(.openAI) { return "Needs an OpenAI API key" }
        if !model.hotkeyRunning { return "Hotkey unavailable" }
        return "Hold \(model.preferences.hotkey.keyCap) to dictate"
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func finishSetup() {
        if model.preferences.onboardingCompleted {
            actions.openPane(model.permissions.requiredGranted ? .models : .privacy)
        } else {
            actions.showOnboarding()
        }
    }

    @objc private func copyLast() {
        if let text = model.lastDelivered?.finalText { TextInserter.copyToClipboard(text) }
    }

    @objc private func pasteLast() { actions.pasteLast() }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        actions.selectDevice(sender.representedObject as? String)
    }

    @objc private func togglePause() {
        model.isPaused.toggle()
        update()
    }

    @objc private func openHistory() { actions.openPane(.history) }
    @objc private func openUsage() { actions.openPane(.usage) }
    @objc private func openHome() { actions.openPane(.home) }
}
