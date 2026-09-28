import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid

enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var explanation: String {
        switch self {
        case .microphone: "Hear you while you hold the dictation key."
        case .accessibility: "Detect the dictation key, see which app you're typing in, and paste your text."
        case .inputMonitoring: "Some Macs also require this for the dictation key to work."
        }
    }

    var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard.fill"
        }
    }

    var settingsURL: URL {
        let anchor = switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

struct PermissionsSnapshot: Equatable {
    var microphone: PermissionStatus = .notDetermined
    var accessibility: PermissionStatus = .notDetermined
    var inputMonitoring: PermissionStatus = .notDetermined

    subscript(kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone: microphone
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }

    /// Microphone and Accessibility are required; Input Monitoring only
    /// matters if the hotkey tap can't start without it.
    var requiredGranted: Bool {
        microphone == .granted && accessibility == .granted
    }
}

enum Permissions {
    static func current() -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphone: microphone(),
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            inputMonitoring: inputMonitoring()
        )
    }

    static func microphone() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func inputMonitoring() -> PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .notDetermined
        }
    }

    /// Shows the system prompt the first time, then opens System Settings.
    @MainActor
    static func request(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            if microphone() == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                openSettings(for: kind)
            }
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                openSettings(for: kind)
            }
        case .inputMonitoring:
            if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
                openSettings(for: kind)
            }
        }
    }

    static func openSettings(for kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    /// Restarts the app; event taps often only start working after a relaunch
    /// once Accessibility/Input Monitoring has been granted.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
