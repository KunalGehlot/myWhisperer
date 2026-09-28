import AppKit
import Carbon.HIToolbox
import CoreGraphics
import MyWhispererCore

/// Watches the global keyboard through a CGEvent tap.
///
/// - The dictation key (Fn or a right-hand modifier) reports press/release.
/// - Holding Shift together with it selects command mode.
/// - While dictating, Space locks hands-free mode and Esc cancels; both key
///   presses are swallowed so they don't reach the frontmost app.
final class HotkeyManager {
    struct Callbacks {
        var pressed: (DictationMode) -> Void
        var released: () -> Void
        var modeChanged: (DictationMode) -> Void
        /// Space while held. Return true to swallow the key.
        var space: () -> Bool
        /// Esc. Return true to swallow the key.
        var escape: () -> Bool
        /// Another key was pressed while the hotkey was held (e.g. fn+arrow):
        /// the user is typing a shortcut, not dictating.
        var interrupted: () -> Void
        /// Whether a dictation is currently recording or processing.
        var isActive: () -> Bool
    }

    var hotkey: HotkeyChoice
    var callbacks: Callbacks

    private(set) var isRunning = false
    /// `defaults write com.mywhisperer.app DebugHotkey -bool true`
    /// logs every modifier change (view with `log stream --predicate 'process == "myWhisperer"'`).
    private let debugLogging = UserDefaults.standard.bool(forKey: "DebugHotkey")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyDown = false
    private var swallowedKeyUps: Set<Int64> = []

    init(hotkey: HotkeyChoice, callbacks: Callbacks) {
        self.hotkey = hotkey
        self.callbacks = callbacks
    }

    /// Starts the tap. Fails without Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            isRunning = false
            return false
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        hotkeyDown = false
    }

    // MARK: Event handling (main run loop)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            handleFlags(event)
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event) ? nil : Unmanaged.passUnretained(event)
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if swallowedKeyUps.remove(code) != nil { return nil }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Runs work after the tap callback returns. An active tap holds up every
    /// keyboard event on the system until it returns, so starting audio or
    /// reading Accessibility inline would make all typing lag.
    private func later(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(work) }
    }

    private func handleFlags(_ event: CGEvent) {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if debugLogging {
            NSLog("myWhisperer key: flagsChanged code=\(code) flags=0x\(String(flags.rawValue, radix: 16))")
        }

        if code == hotkey.keyCode {
            let down = hotkey.isDown(flags)
            if down && !hotkeyDown {
                hotkeyDown = true
                let mode: DictationMode = flags.contains(.maskShift) && hotkey != .rightControl ? .command : .dictate
                later { [callbacks] in callbacks.pressed(mode) }
            } else if !down && hotkeyDown {
                hotkeyDown = false
                later { [callbacks] in callbacks.released() }
            }
            return
        }

        // Shift pressed while holding the hotkey switches to command mode.
        if hotkeyDown, code == kVK_Shift || code == kVK_RightShift, flags.contains(.maskShift) {
            later { [callbacks] in callbacks.modeChanged(.command) }
        }
    }

    /// Returns true to swallow the event.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if code == Int64(kVK_Escape) {
            let active = MainActor.assumeIsolated { callbacks.isActive() }
            guard active else { return false }
            let consumed = MainActor.assumeIsolated { callbacks.escape() }
            if consumed { swallowedKeyUps.insert(code) }
            return consumed
        }

        guard hotkeyDown else { return false }

        if code == Int64(kVK_Space) {
            if isRepeat { return true }
            let consumed = MainActor.assumeIsolated { callbacks.space() }
            if consumed { swallowedKeyUps.insert(code) }
            return consumed
        }

        // Any other key while holding the hotkey is a keyboard shortcut.
        later { [callbacks] in callbacks.interrupted() }
        return false
    }
}

extension HotkeyChoice {
    /// Virtual key code of the physical key.
    var keyCode: Int {
        switch self {
        case .fn: kVK_Function
        case .rightOption: kVK_RightOption
        case .rightCommand: kVK_RightCommand
        case .rightControl: kVK_RightControl
        }
    }

    /// Whether the key is down according to a flagsChanged event. Right-hand
    /// modifiers use device-specific bits so the left key doesn't trigger.
    func isDown(_ flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        switch self {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .rightOption: return raw & 0x40 != 0      // NX_DEVICERALTKEYMASK
        case .rightCommand: return raw & 0x10 != 0     // NX_DEVICERCMDKEYMASK
        case .rightControl: return raw & 0x2000 != 0   // NX_DEVICERCTLKEYMASK
        }
    }
}

/// A classic Carbon hotkey (no permissions needed), used for
/// "Paste last transcript" (⌃⌘V).
final class GlobalShortcut {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var registry: [UInt32: GlobalShortcut] = [:]
    private static var nextID: UInt32 = 1

    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        let id = Self.nextID
        Self.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            GlobalShortcut.registry[hotKeyID.id]?.action()
            return noErr
        }, 1, &eventType, nil, &handler)
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D59_5748), id: id) // "MYWH"
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
        Self.registry[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
