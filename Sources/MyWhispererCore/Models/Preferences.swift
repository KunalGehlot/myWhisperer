import Foundation

/// Which key starts dictation.
public enum HotkeyChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fn: "Fn (Globe)"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        }
    }

    /// Short label for a key cap.
    public var keyCap: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "right ⌥"
        case .rightCommand: "right ⌘"
        case .rightControl: "right ⌃"
        }
    }
}

/// How myWhisperer behaves in a particular app.
public enum AppRuleMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Full context-aware cleanup.
    case normal
    /// Insert the transcript without LLM cleanup.
    case raw
    /// Ignore the hotkey in this app.
    case disabled

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: "Smart cleanup"
        case .raw: "Raw transcript"
        case .disabled: "Disabled"
        }
    }
}

public struct AppRule: Codable, Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var appName: String
    public var mode: AppRuleMode
    /// Overrides the automatic category, e.g. treat Notion as "work".
    public var category: AppCategory?

    public var id: String { bundleID }

    public init(bundleID: String, appName: String, mode: AppRuleMode = .normal, category: AppCategory? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.mode = mode
        self.category = category
    }
}

/// All user settings. Every field decodes with a default so adding settings
/// never breaks an existing preferences file.
public struct Preferences: Codable, Equatable, Sendable {
    public var onboardingCompleted = false

    // Hotkey
    public var hotkey: HotkeyChoice = .fn
    /// Double-tap the hotkey (or press Space while holding) to keep listening
    /// hands-free until the hotkey is pressed again.
    public var handsFreeEnabled = true

    // Speech-to-text
    public var transcriptionModel = ModelCatalog.defaultTranscriptionModel
    /// Expected spoken languages (ISO 639-1). Empty = auto-detect.
    public var languages: [String] = ["en", "de"]

    // Refinement
    public var refinerProvider = ModelCatalog.defaultRefinerProvider
    public var anthropicModel = ModelCatalog.defaultAnthropicModel
    public var openAIRefinerModel = ModelCatalog.defaultOpenAIModel
    /// Seconds to wait for cleanup before inserting the raw transcript.
    public var refinerTimeout: Double = 4

    // Context & privacy
    /// Send the text around the cursor to the refiner.
    public var useFieldContext = true
    public var historyRetentionDays: Int? = nil

    // Styles and app rules
    public var styles: [AppCategory: CategoryStyle] = [:]
    public var appRules: [AppRule] = []

    // Feedback
    public var soundsEnabled = true
    public var soundVolume: Double = 0.5
    /// Keep the clipboard as it was before myWhisperer pasted.
    public var restoreClipboard = true

    // Audio
    /// CoreAudio device UID; nil = system default input.
    public var inputDeviceUID: String?

    public init() {}

    public func style(for category: AppCategory) -> CategoryStyle {
        styles[category] ?? .defaultStyle(for: category)
    }

    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }
    }

    public var refinerModel: String {
        switch refinerProvider {
        case .anthropic: anthropicModel
        case .openAI: openAIRefinerModel
        case .none: ""
        }
    }

    // MARK: Codable with per-field defaults

    private enum CodingKeys: String, CodingKey {
        case onboardingCompleted, hotkey, handsFreeEnabled, transcriptionModel, languages,
             refinerProvider, anthropicModel, openAIRefinerModel, refinerTimeout,
             useFieldContext, historyRetentionDays, styles, appRules, soundsEnabled,
             soundVolume, restoreClipboard, inputDeviceUID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        onboardingCompleted = (try? c.decode(Bool.self, forKey: .onboardingCompleted)) ?? d.onboardingCompleted
        hotkey = (try? c.decode(HotkeyChoice.self, forKey: .hotkey)) ?? d.hotkey
        handsFreeEnabled = (try? c.decode(Bool.self, forKey: .handsFreeEnabled)) ?? d.handsFreeEnabled
        transcriptionModel = (try? c.decode(String.self, forKey: .transcriptionModel)) ?? d.transcriptionModel
        languages = (try? c.decode([String].self, forKey: .languages)) ?? d.languages
        refinerProvider = (try? c.decode(RefinerProvider.self, forKey: .refinerProvider)) ?? d.refinerProvider
        anthropicModel = (try? c.decode(String.self, forKey: .anthropicModel)) ?? d.anthropicModel
        openAIRefinerModel = (try? c.decode(String.self, forKey: .openAIRefinerModel)) ?? d.openAIRefinerModel
        refinerTimeout = (try? c.decode(Double.self, forKey: .refinerTimeout)) ?? d.refinerTimeout
        useFieldContext = (try? c.decode(Bool.self, forKey: .useFieldContext)) ?? d.useFieldContext
        historyRetentionDays = (try? c.decodeIfPresent(Int.self, forKey: .historyRetentionDays)) ?? d.historyRetentionDays
        styles = (try? c.decode([AppCategory: CategoryStyle].self, forKey: .styles)) ?? d.styles
        appRules = (try? c.decode([AppRule].self, forKey: .appRules)) ?? d.appRules
        soundsEnabled = (try? c.decode(Bool.self, forKey: .soundsEnabled)) ?? d.soundsEnabled
        soundVolume = (try? c.decode(Double.self, forKey: .soundVolume)) ?? d.soundVolume
        restoreClipboard = (try? c.decode(Bool.self, forKey: .restoreClipboard)) ?? d.restoreClipboard
        inputDeviceUID = (try? c.decodeIfPresent(String.self, forKey: .inputDeviceUID)) ?? d.inputDeviceUID
    }
}
