import Foundation

/// Inputs for processing one recorded utterance.
public struct DictationJob: Sendable {
    public var mode: DictationMode
    public var clip: AudioClip
    /// Already reduced according to the user's privacy settings.
    public var context: AppContext?
    public var category: AppCategory
    public var style: CategoryStyle
    public var dictionary: [String]
    public var snippets: [Snippet]
    public var languages: [String]
    public var refinerTimeout: Double

    public init(
        mode: DictationMode = .dictate,
        clip: AudioClip,
        context: AppContext? = nil,
        category: AppCategory = .other,
        style: CategoryStyle = .defaultStyle(for: .other),
        dictionary: [String] = [],
        snippets: [Snippet] = [],
        languages: [String] = [],
        refinerTimeout: Double = 4
    ) {
        self.mode = mode
        self.clip = clip
        self.context = context
        self.category = category
        self.style = style
        self.dictionary = dictionary
        self.snippets = snippets
        self.languages = languages
        self.refinerTimeout = refinerTimeout
    }
}

public struct DictationResult: Sendable, Equatable {
    public enum Skip: Sendable, Equatable {
        /// The clip had no speech-level audio; nothing was sent anywhere.
        case silent
        /// The recognizer returned nothing usable.
        case noSpeech
    }

    public var rawText: String
    public var finalText: String
    public var timings: StageTimings
    /// Set when cleanup ran and its output was used.
    public var refinerModel: String?
    /// Why cleanup didn't apply, when it was expected to.
    public var refinerNote: String?
    public var skipped: Skip?
    /// Every billable request made for this dictation.
    public var usage: [UsageSample] = []

    public var estimatedCost: Double? {
        let costs = usage.compactMap(\.estimatedCost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }
}

public enum DictationError: Error, Equatable, LocalizedError, Sendable {
    case transcriptionFailed(ProviderError)
    case commandNeedsRefiner
    case commandFailed(ProviderError)

    public var errorDescription: String? {
        switch self {
        case .transcriptionFailed(let error): error.errorDescription
        case .commandNeedsRefiner: "Command mode needs a cleanup model. Choose one in Settings → Models."
        case .commandFailed(let error): error.errorDescription
        }
    }

    public var shortDescription: String {
        switch self {
        case .transcriptionFailed(let error): error.shortDescription
        case .commandNeedsRefiner: "Turn on a cleanup model"
        case .commandFailed(let error): error.shortDescription
        }
    }

    public var providerError: ProviderError? {
        switch self {
        case .transcriptionFailed(let e), .commandFailed(let e): e
        case .commandNeedsRefiner: nil
        }
    }
}

/// Speech → text → cleanup → snippets → insertion-ready text.
public struct DictationPipeline: Sendable {
    public var transcriber: any Transcriber
    public var transcriptionModel: String
    public var refiner: (any Refiner)?

    /// Less voiced audio than this is treated as silence.
    public static let minimumVoicedSeconds = 0.15

    public init(transcriber: any Transcriber, transcriptionModel: String, refiner: (any Refiner)?) {
        self.transcriber = transcriber
        self.transcriptionModel = transcriptionModel
        self.refiner = refiner
    }

    public func run(_ job: DictationJob) async throws -> DictationResult {
        let start = ContinuousClock.now
        var timings = StageTimings()
        var usage: [UsageSample] = []

        if job.mode == .command, refiner == nil {
            throw DictationError.commandNeedsRefiner
        }

        guard AudioLevel.voicedSeconds(job.clip) >= Self.minimumVoicedSeconds else {
            return DictationResult(rawText: "", finalText: "", timings: timings, skipped: .silent)
        }

        // 1. Speech to text.
        let prompt = TranscriptionPrompt.make(
            dictionary: job.dictionary,
            textBeforeCursor: job.mode == .dictate ? job.context?.textBeforeCursor : nil
        )
        let transcribeStart = ContinuousClock.now
        let recognized: String
        do {
            let transcription = try await transcriber.transcribe(
                job.clip, prompt: prompt, keywords: job.dictionary, languages: job.languages)
            recognized = transcription.text
            if let sample = transcription.usage { usage.append(sample) }
        } catch let error as ProviderError {
            throw DictationError.transcriptionFailed(error)
        }
        timings.transcribeMs = Self.milliseconds(since: transcribeStart)

        let raw = HallucinationFilter.clean(recognized)
        guard !raw.isEmpty else {
            timings.totalMs = Self.milliseconds(since: start)
            return DictationResult(rawText: recognized, finalText: "", timings: timings, skipped: .noSpeech, usage: usage)
        }

        // 2. Cleanup (or the command's transformation).
        var text = raw
        var refinerModel: String?
        var refinerNote: String?
        if let refiner {
            let request = RefinerRequest(
                mode: job.mode,
                transcript: raw,
                context: job.context,
                category: job.category,
                style: job.style,
                dictionary: job.dictionary,
                snippetTriggers: job.snippets.map(\.trigger)
            )
            let refineStart = ContinuousClock.now
            do {
                let reply = try await Self.withTimeout(seconds: job.refinerTimeout) {
                    try await refiner.complete(
                        system: RefinerPrompt.system(for: job.mode),
                        user: RefinerPrompt.userMessage(for: request)
                    )
                }
                timings.refineMs = Self.milliseconds(since: refineStart)
                usage.append(UsageSample(provider: refiner.provider, kind: .cleanup, model: refiner.modelID,
                                         inputTokens: reply.inputTokens, outputTokens: reply.outputTokens))
                if let parsed = OutputParser.extract(reply.text) {
                    if parsed.isEmpty && TextStats.wordCount(raw) > 2 {
                        // The model decided a real utterance was filler. Don't
                        // lose the user's words over it.
                        refinerNote = "Cleanup returned nothing; used the raw transcript."
                    } else {
                        text = parsed
                        refinerModel = refiner.modelID
                    }
                } else {
                    refinerNote = "Cleanup reply was malformed; used the raw transcript."
                }
            } catch let error as ProviderError {
                timings.refineMs = Self.milliseconds(since: refineStart)
                if job.mode == .command { throw DictationError.commandFailed(error) }
                refinerNote = "Cleanup skipped: \(error.shortDescription.lowercased())."
            }
        }

        // 3. Deterministic post-processing.
        if job.mode == .dictate {
            text = SnippetExpander.expand(text, snippets: job.snippets)
        }
        let replacingSelection = job.context?.hasSelection ?? false
        text = InsertionFormatter.format(
            text,
            before: replacingSelection && job.mode == .command ? nil : job.context?.textBeforeCursor,
            fixCapitalization: refinerModel == nil
        )

        timings.totalMs = Self.milliseconds(since: start)
        return DictationResult(
            rawText: raw,
            finalText: text,
            timings: timings,
            refinerModel: refinerModel,
            refinerNote: refinerNote,
            skipped: text.isEmpty ? .noSpeech : nil,
            usage: usage
        )
    }

    static func milliseconds(since instant: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - instant
        return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }

    static func withTimeout<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ProviderError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw ProviderError.timedOut }
            return result
        }
    }
}
