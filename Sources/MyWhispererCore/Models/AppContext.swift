import Foundation

/// Where the user is dictating: captured at hotkey-down, before any UI shows.
public struct AppContext: Codable, Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var windowTitle: String?
    public var urlHost: String?
    /// Text immediately before the insertion point (bounded).
    public var textBeforeCursor: String?
    /// Text immediately after the insertion point (bounded).
    public var textAfterCursor: String?
    public var selectedText: String?
    /// True for password fields; no text is captured from them.
    public var isSecureField: Bool

    public init(
        bundleID: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        urlHost: String? = nil,
        textBeforeCursor: String? = nil,
        textAfterCursor: String? = nil,
        selectedText: String? = nil,
        isSecureField: Bool = false
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.urlHost = urlHost
        self.textBeforeCursor = textBeforeCursor
        self.textAfterCursor = textAfterCursor
        self.selectedText = selectedText
        self.isSecureField = isSecureField
    }

    public var category: AppCategory {
        AppClassifier.category(bundleID: bundleID, urlHost: urlHost)
    }

    public var hasSelection: Bool {
        !(selectedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Same context with the typed-text fields dropped (privacy setting).
    public var withoutFieldText: AppContext {
        var copy = self
        copy.textBeforeCursor = nil
        copy.textAfterCursor = nil
        copy.selectedText = nil
        return copy
    }

    /// Limits for how much field text is captured and sent to providers.
    public static let maxTextBeforeCursor = 1_500
    public static let maxTextAfterCursor = 300
    public static let maxSelectedText = 4_000
}
