import Foundation

/// Every provider model ID the app knows about, in one place.
/// IDs verified against provider docs on 2026-09-28.
public enum ModelCatalog {
    public struct Option: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
    }

    // MARK: Speech-to-text (OpenAI /v1/audio/transcriptions)

    public static let defaultTranscriptionModel = "gpt-transcribe"

    public static let transcriptionModels: [Option] = [
        Option(id: "gpt-transcribe", title: "GPT Transcribe",
               detail: "Recommended. Most accurate; understands mixed languages."),
        Option(id: "whisper-1", title: "Whisper",
               detail: "Classic Whisper. Auto-detects language per clip."),
        Option(id: "gpt-4o-transcribe", title: "GPT-4o Transcribe",
               detail: "Previous generation."),
        Option(id: "gpt-4o-mini-transcribe", title: "GPT-4o mini Transcribe",
               detail: "Cheapest; slightly less accurate."),
    ]

    /// Models that accept a list of expected languages (`languages`) rather
    /// than a single `language`.
    static let multiLanguageTranscriptionModels: Set<String> = ["gpt-transcribe"]

    /// Models that accept a `keywords` list for domain terms.
    static let keywordTranscriptionModels: Set<String> = ["gpt-transcribe"]

    // MARK: Refinement

    public static let defaultRefinerProvider = RefinerProvider.anthropic
    public static let defaultAnthropicModel = "claude-haiku-4-5"
    public static let defaultOpenAIModel = "gpt-6-luna"

    public static let anthropicModels: [Option] = [
        Option(id: "claude-haiku-4-5", title: "Claude Haiku 4.5",
               detail: "Fastest. Recommended for dictation."),
        Option(id: "claude-sonnet-5", title: "Claude Sonnet 5",
               detail: "Smarter rewrites, a little slower."),
        Option(id: "claude-opus-5", title: "Claude Opus 5",
               detail: "Highest quality, noticeably slower."),
    ]

    public static let openAIModels: [Option] = [
        Option(id: "gpt-6-luna", title: "GPT-6 Luna",
               detail: "OpenAI's most efficient model."),
    ]

    public static func title(for modelID: String) -> String {
        (transcriptionModels + anthropicModels + openAIModels)
            .first { $0.id == modelID }?.title ?? modelID
    }

    // MARK: Languages offered as transcription hints

    public static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("de", "German"), ("fr", "French"), ("es", "Spanish"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"),
        ("tr", "Turkish"), ("ru", "Russian"), ("uk", "Ukrainian"), ("sv", "Swedish"),
        ("da", "Danish"), ("no", "Norwegian"), ("fi", "Finnish"), ("cs", "Czech"),
        ("hi", "Hindi"), ("ar", "Arabic"), ("zh", "Chinese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("id", "Indonesian"), ("vi", "Vietnamese"), ("th", "Thai"),
    ]

}

public enum RefinerProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case anthropic
    case openAI
    /// Insert the transcript as-is (only deterministic cleanup).
    case none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .none: "Off (raw transcript)"
        }
    }
}
