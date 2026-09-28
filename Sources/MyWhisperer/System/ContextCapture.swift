import AppKit
import ApplicationServices
import MyWhispererCore

/// Reads where the user is typing through the Accessibility API.
final class ContextCapture: ContextProvider {
    /// Electron/Chromium apps only expose their text to AX when asked.
    private var enabledManualAX: Set<pid_t> = []
    /// Total time allowed for one capture; a hung app must not stall dictation.
    private let budget: TimeInterval = 0.25
    private var deadline = Date.distantFuture
    private var activationObserver: NSObjectProtocol?

    /// What the last capture found (lengths only, never the text itself).
    private(set) var lastSummary: [String: Any] = [:]

    init() {
        // Ask Electron/Chromium apps to build their accessibility tree as soon
        // as they come to the front, so it's ready by the time the key is held.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.enableManualAccessibility(app.processIdentifier)
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            enableManualAccessibility(pid)
        }
    }

    private func enableManualAccessibility(_ pid: pid_t) {
        guard AXIsProcessTrusted(), !enabledManualAX.contains(pid) else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        enabledManualAX.insert(pid)
    }

    var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func captureContext() -> AppContext {
        let started = Date()
        let context = capture()
        let summary: [String: Any] = [
            "app": context.appName ?? "?",
            "bundleID": context.bundleID ?? "?",
            "category": context.category.rawValue,
            "ms": Int(Date().timeIntervalSince(started) * 1000),
            "windowTitle": context.windowTitle != nil,
            "urlHost": context.urlHost ?? "",
            "beforeChars": context.textBeforeCursor?.count ?? -1,
            "afterChars": context.textAfterCursor?.count ?? -1,
            "selectionChars": context.selectedText?.count ?? -1,
            "secure": context.isSecureField,
            "timedOut": timeUp,
        ]
        lastSummary = summary
        NSLog("myWhisperer context: \(summary.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        return context
    }

    private func capture() -> AppContext {
        deadline = Date().addingTimeInterval(budget)
        let app = NSWorkspace.shared.frontmostApplication
        var context = AppContext(bundleID: app?.bundleIdentifier, appName: app?.localizedName)
        guard AXIsProcessTrusted(), let app else { return context }

        // Applies to every element: a single slow reply can't eat the budget.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.1)
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        enableManualAccessibility(pid)

        if let window: AXUIElement = copy(appElement, kAXFocusedWindowAttribute) {
            context.windowTitle = copy(window, kAXTitleAttribute)
        }

        guard let focused: AXUIElement = copy(appElement, kAXFocusedUIElementAttribute) else { return context }

        if let subrole: String = copy(focused, kAXSubroleAttribute), subrole == (kAXSecureTextFieldSubrole as String) {
            context.isSecureField = true
            return context
        }

        if AppClassifier.browserBundleIDs.contains(app.bundleIdentifier ?? "") {
            context.urlHost = browserHost(from: focused)
        }

        readText(from: focused, into: &context)
        return context
    }

    // MARK: Text around the cursor

    private func readText(from element: AXUIElement, into context: inout AppContext) {
        let selected: String? = copy(element, kAXSelectedTextAttribute)
        context.selectedText = selected.map { String($0.prefix(AppContext.maxSelectedText)) }

        guard let rangeValue: AXValue = copy(element, kAXSelectedTextRangeAttribute) else {
            // No caret information: at least say whether the field is empty.
            if let value: String = copy(element, kAXValueAttribute) {
                context.textBeforeCursor = String(value.suffix(AppContext.maxTextBeforeCursor))
            }
            return
        }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.location >= 0 else { return }

        let total: Int? = copyNumber(element, kAXNumberOfCharactersAttribute)
        let beforeStart = max(0, range.location - AppContext.maxTextBeforeCursor)
        context.textBeforeCursor = string(in: element, location: beforeStart, length: range.location - beforeStart)

        let afterStart = range.location + range.length
        var afterLength = AppContext.maxTextAfterCursor
        if let total { afterLength = max(0, min(afterLength, total - afterStart)) }
        if afterLength > 0 {
            context.textAfterCursor = string(in: element, location: afterStart, length: afterLength)
        } else {
            context.textAfterCursor = ""
        }
    }

    /// Text in a UTF-16 range, via the parameterized attribute when available
    /// (cheap even for huge documents) or by slicing the full value.
    private func string(in element: AXUIElement, location: Int, length: Int) -> String? {
        guard length > 0 else { return "" }
        var cfRange = CFRange(location: location, length: length)
        if let rangeValue = AXValueCreate(.cfRange, &cfRange) {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                          rangeValue, &result) == .success,
               let text = result as? String {
                return text
            }
        }
        guard let value: String = copy(element, kAXValueAttribute) else { return nil }
        let utf16 = value.utf16
        guard location <= utf16.count else { return nil }
        let start = utf16.index(utf16.startIndex, offsetBy: location)
        let end = utf16.index(start, offsetBy: min(length, utf16.count - location))
        return String(utf16[start..<end])
    }

    // MARK: Browser URL

    private func browserHost(from element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let node = current, !timeUp else { break }
            if let role: String = copy(node, kAXRoleAttribute), role == "AXWebArea" {
                if let url: URL = copy(node, kAXURLAttribute) { return url.host }
                if let urlString: String = copy(node, kAXURLAttribute) { return URL(string: urlString)?.host }
            }
            current = copy(node, kAXParentAttribute)
        }
        return nil
    }

    // MARK: AX helpers

    private var timeUp: Bool { Date() > deadline }

    private func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        guard !timeUp else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self, CFGetTypeID(value) == AXUIElementGetTypeID() { return (value as! T) }
        if T.self == AXValue.self, CFGetTypeID(value) == AXValueGetTypeID() { return (value as! T) }
        return value as? T
    }

    private func copyNumber(_ element: AXUIElement, _ attribute: String) -> Int? {
        let number: NSNumber? = copy(element, attribute)
        return number?.intValue
    }
}
