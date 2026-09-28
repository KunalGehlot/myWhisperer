import Foundation

/// Per-stage latency of one dictation, in milliseconds.
public struct StageTimings: Codable, Equatable, Sendable {
    public var transcribeMs: Int?
    public var refineMs: Int?
    public var totalMs: Int?

    public init(transcribeMs: Int? = nil, refineMs: Int? = nil, totalMs: Int? = nil) {
        self.transcribeMs = transcribeMs
        self.refineMs = refineMs
        self.totalMs = totalMs
    }
}

public enum DictationMode: String, Codable, Sendable {
    /// Speech becomes text at the cursor.
    case dictate
    /// Speech is an instruction applied to the selected text.
    case command
}

public enum DeliveryStatus: String, Codable, Sendable {
    case inserted
    /// Couldn't paste into the app; the text was left on the clipboard.
    case copied
    case failed
}

/// One dictation, kept so nothing the user says is ever lost.
public struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var mode: DictationMode
    public var appName: String?
    public var bundleID: String?
    public var category: AppCategory
    /// Recognizer output before cleanup.
    public var rawText: String
    /// What was (or would have been) inserted.
    public var finalText: String
    public var audioSeconds: Double
    public var timings: StageTimings
    public var transcriptionModel: String
    /// Nil when cleanup was off or failed.
    public var refinerModel: String?
    /// Why cleanup was skipped, if it was.
    public var refinerNote: String?
    public var status: DeliveryStatus
    /// Estimated API cost of this dictation in USD (nil for older entries).
    public var costUSD: Double?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        mode: DictationMode = .dictate,
        appName: String? = nil,
        bundleID: String? = nil,
        category: AppCategory = .other,
        rawText: String,
        finalText: String,
        audioSeconds: Double,
        timings: StageTimings = StageTimings(),
        transcriptionModel: String,
        refinerModel: String? = nil,
        refinerNote: String? = nil,
        status: DeliveryStatus = .inserted,
        costUSD: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.appName = appName
        self.bundleID = bundleID
        self.category = category
        self.rawText = rawText
        self.finalText = finalText
        self.audioSeconds = audioSeconds
        self.timings = timings
        self.transcriptionModel = transcriptionModel
        self.refinerModel = refinerModel
        self.refinerNote = refinerNote
        self.status = status
        self.costUSD = costUSD
    }

    public var wordCount: Int { TextStats.wordCount(finalText) }
}
