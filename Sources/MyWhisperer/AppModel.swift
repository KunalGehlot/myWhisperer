import AppKit
import Observation
import MyWhispererCore
import ServiceManagement

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case home, history, dictionary, snippets, styles
    case general, models, usage, audio, apps, privacy, about

    var id: String { rawValue }

    static let library: [Pane] = [.home, .history, .dictionary, .snippets, .styles]
    static let settings: [Pane] = [.general, .models, .usage, .audio, .apps, .privacy, .about]

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .snippets: "Snippets"
        case .styles: "Styles"
        case .general: "General"
        case .models: "Models & Keys"
        case .usage: "Usage & Costs"
        case .audio: "Microphone"
        case .apps: "Apps"
        case .privacy: "Privacy & Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .styles: "textformat"
        case .general: "gearshape"
        case .models: "cpu"
        case .usage: "chart.bar.xaxis"
        case .audio: "mic"
        case .apps: "square.grid.2x2"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

enum KeyState: Equatable {
    case missing
    case saved
    case checking
    case valid
    case invalid(String)
}

/// Refiner stand-in when the chosen provider has no key: dictation still
/// works (raw), and history explains why cleanup was skipped.
private struct MissingKeyRefiner: Refiner {
    let providerName: String
    let modelID: String
    var provider: UsageProvider { .anthropic }
    func complete(system: String, user: String) async throws -> RefinerReply {
        throw ProviderError.missingAPIKey(provider: providerName)
    }
}

/// All app state. Views observe it; the dictation controller reports to it.
@MainActor
@Observable
final class AppModel: DictationHost {
    // MARK: Persisted

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            try? preferencesStore.save(preferences)
            onPreferencesChanged?(oldValue)
        }
    }

    var dictionary: [DictionaryEntry] {
        didSet { try? dictionaryStore.save(dictionary) }
    }

    var snippets: [Snippet] {
        didSet { try? snippetsStore.save(snippets) }
    }

    private(set) var history: [HistoryEntry] {
        didSet { if persistHistory { try? historyStore.save(history) } }
    }

    private(set) var usage: UsageLedger {
        didSet { if persistHistory { try? usageStore.save(usage) } }
    }

    // MARK: Runtime

    private(set) var phase: DictationPhase = .idle
    var audioLevel: Float = 0
    var isPaused = false
    var permissions = PermissionsSnapshot()
    var hotkeyRunning = false
    /// The event tap failed even though Accessibility is granted.
    var hotkeyNeedsRelaunch = false
    var inputDevices: [AudioInputDevice] = []
    var keyStates: [APIKeyKind: KeyState] = [:]
    var retrying: Set<UUID> = []
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    // MARK: Wiring

    @ObservationIgnored var onPreferencesChanged: ((Preferences) -> Void)?
    @ObservationIgnored var onPhaseChanged: ((DictationPhase) -> Void)?
    @ObservationIgnored var openPane: ((Pane) -> Void)?
    @ObservationIgnored var showOnboarding: (() -> Void)?
    @ObservationIgnored var insertText: ((String) async -> InsertOutcome)?
    /// Starts/stops mic level metering for the microphone test screens.
    @ObservationIgnored var micMonitor: ((Bool) -> Void)?
    @ObservationIgnored let sounds = SoundPlayer()

    @ObservationIgnored private let preferencesStore: JSONFileStore<Preferences>
    @ObservationIgnored private let dictionaryStore: JSONFileStore<[DictionaryEntry]>
    @ObservationIgnored private let snippetsStore: JSONFileStore<[Snippet]>
    @ObservationIgnored private let historyStore: JSONFileStore<[HistoryEntry]>
    @ObservationIgnored private let usageStore: JSONFileStore<UsageLedger>
    @ObservationIgnored private let persistHistory: Bool
    @ObservationIgnored let directory: URL
    @ObservationIgnored private var apiKeys: [APIKeyKind: String] = [:]

    static let maxHistoryEntries = 5_000

    init(directory: URL = JSONFileStore<Preferences>.defaultDirectory, readKeychain: Bool = true, persistHistory: Bool = true) {
        self.directory = directory
        self.persistHistory = persistHistory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferencesStore = JSONFileStore(filename: "preferences.json", directory: directory)
        dictionaryStore = JSONFileStore(filename: "dictionary.json", directory: directory)
        snippetsStore = JSONFileStore(filename: "snippets.json", directory: directory)
        historyStore = JSONFileStore(filename: "history.json", directory: directory)
        usageStore = JSONFileStore(filename: "usage.json", directory: directory)

        preferences = preferencesStore.load() ?? Preferences()
        dictionary = dictionaryStore.load() ?? []
        snippets = snippetsStore.load() ?? []
        history = historyStore.load() ?? []
        usage = usageStore.load() ?? UsageLedger()

        if readKeychain {
            for kind in APIKeyKind.allCases {
                if let key = Keychain.apiKey(kind) {
                    apiKeys[kind] = key
                    keyStates[kind] = .saved
                } else {
                    keyStates[kind] = .missing
                }
            }
        }
        sounds.volume = Float(preferences.soundVolume)
        pruneHistory()
    }

    // MARK: DictationHost

    var dictionaryTerms: [String] { dictionary.map(\.term) }

    func makePipeline(useRefiner: Bool) throws -> DictationPipeline {
        guard let openAIKey = apiKeys[.openAI] else {
            throw ProviderError.missingAPIKey(provider: "OpenAI")
        }
        let transcriber = OpenAITranscriber(apiKey: openAIKey, model: preferences.transcriptionModel)
        var refiner: (any Refiner)?
        if useRefiner {
            switch preferences.refinerProvider {
            case .anthropic:
                if let key = apiKeys[.anthropic] {
                    refiner = AnthropicRefiner(apiKey: key, model: preferences.anthropicModel)
                } else {
                    refiner = MissingKeyRefiner(providerName: "Anthropic", modelID: preferences.anthropicModel)
                }
            case .openAI:
                refiner = OpenAIRefiner(apiKey: openAIKey, model: preferences.openAIRefinerModel)
            case .none:
                refiner = nil
            }
        }
        return DictationPipeline(transcriber: transcriber, transcriptionModel: preferences.transcriptionModel, refiner: refiner)
    }

    func dictationPhaseChanged(_ phase: DictationPhase) {
        self.phase = phase
        onPhaseChanged?(phase)
    }

    func play(_ cue: SoundCue) {
        guard preferences.soundsEnabled else { return }
        sounds.volume = Float(preferences.soundVolume)
        sounds.play(cue)
    }

    func record(_ entry: HistoryEntry, failedAudio: AudioClip?) {
        if let failedAudio {
            try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
            try? failedAudio.wavData.write(to: recordingURL(for: entry.id))
        }
        history.insert(entry, at: 0)
        pruneHistory()
    }

    func recordUsage(_ samples: [UsageSample]) {
        usage.record(samples)
    }

    /// Estimated spend since the start of the current calendar month.
    var spentThisMonth: Double {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start
        return usage.total(since: start).cost
    }

    // MARK: History

    var lastDelivered: HistoryEntry? {
        history.first { $0.status != .failed && !$0.finalText.isEmpty }
    }

    var recordingsDirectory: URL { directory.appendingPathComponent("Recordings", isDirectory: true) }

    func recordingURL(for id: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(id.uuidString).wav")
    }

    func hasRecording(_ entry: HistoryEntry) -> Bool {
        FileManager.default.fileExists(atPath: recordingURL(for: entry.id).path)
    }

    func deleteHistory(_ ids: Set<UUID>) {
        history.removeAll { ids.contains($0.id) }
        for id in ids { try? FileManager.default.removeItem(at: recordingURL(for: id)) }
    }

    func clearHistory() {
        history.removeAll()
        try? FileManager.default.removeItem(at: recordingsDirectory)
    }

    func pruneHistory() {
        var kept = history
        if let days = preferences.historyRetentionDays,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
            kept.removeAll { $0.date < cutoff }
        }
        if kept.count > Self.maxHistoryEntries {
            kept = Array(kept.prefix(Self.maxHistoryEntries))
        }
        if kept.count != history.count {
            let removed = Set(history.map(\.id)).subtracting(kept.map(\.id))
            history = kept
            for id in removed { try? FileManager.default.removeItem(at: recordingURL(for: id)) }
        }
    }

    /// Re-runs a failed dictation from its saved audio; the result is copied
    /// to the clipboard (the original cursor position is long gone).
    func retry(_ entry: HistoryEntry) {
        guard !retrying.contains(entry.id),
              let data = try? Data(contentsOf: recordingURL(for: entry.id)),
              let clip = AudioClip(wav: data) else { return }
        retrying.insert(entry.id)
        let prefs = preferences
        let job = DictationJob(
            mode: entry.mode,
            clip: clip,
            context: AppContext(bundleID: entry.bundleID, appName: entry.appName),
            category: entry.category,
            style: prefs.style(for: entry.category),
            dictionary: dictionaryTerms,
            snippets: snippets,
            languages: prefs.languages,
            refinerTimeout: max(prefs.refinerTimeout, 8)
        )
        Task {
            defer { retrying.remove(entry.id) }
            do {
                let pipeline = try makePipeline(useRefiner: prefs.rule(for: entry.bundleID)?.mode != .raw)
                let result = try await pipeline.run(job)
                recordUsage(result.usage)
                guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
                var updated = history[index]
                updated.rawText = result.rawText
                updated.finalText = result.finalText.trimmingCharacters(in: .whitespaces)
                updated.timings = result.timings
                updated.refinerModel = result.refinerModel
                updated.refinerNote = result.skipped != nil ? "No speech detected." : result.refinerNote
                updated.transcriptionModel = prefs.transcriptionModel
                updated.status = result.skipped != nil ? .failed : .copied
                updated.costUSD = result.estimatedCost
                history[index] = updated
                if result.skipped == nil {
                    TextInserter.copyToClipboard(updated.finalText)
                    try? FileManager.default.removeItem(at: recordingURL(for: entry.id))
                    play(.stop)
                }
            } catch {
                guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
                history[index].refinerNote = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                play(.error)
            }
        }
    }

    func pasteLast() {
        guard let text = lastDelivered?.finalText else { return }
        Task { _ = await insertText?(text) }
    }

    // MARK: Vocabulary

    func addDictionaryTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !dictionary.contains(where: { $0.term.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        dictionary.insert(DictionaryEntry(term: trimmed), at: 0)
    }

    func removeDictionaryTerm(_ entry: DictionaryEntry) {
        dictionary.removeAll { $0.id == entry.id }
    }

    func saveSnippet(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.insert(snippet, at: 0)
        }
    }

    func deleteSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
    }

    // MARK: API keys

    func hasKey(_ kind: APIKeyKind) -> Bool { apiKeys[kind] != nil }

    func maskedKey(_ kind: APIKeyKind) -> String? {
        guard let key = apiKeys[kind], key.count > 8 else { return nil }
        return String(key.prefix(7)) + "…" + String(key.suffix(4))
    }

    /// Stores (or clears) a key and validates it with a real request.
    func setAPIKey(_ value: String, for kind: APIKeyKind) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Keychain.setAPIKey(nil, for: kind)
            apiKeys[kind] = nil
            keyStates[kind] = .missing
            return
        }
        keyStates[kind] = .checking
        do {
            switch kind {
            case .openAI: try await KeyValidator.validateOpenAI(trimmed)
            case .anthropic: try await KeyValidator.validateAnthropic(trimmed)
            }
            Keychain.setAPIKey(trimmed, for: kind)
            apiKeys[kind] = trimmed
            keyStates[kind] = .valid
        } catch let error as ProviderError {
            if case .network = error {
                // Offline: keep the key, it will be checked on first use.
                Keychain.setAPIKey(trimmed, for: kind)
                apiKeys[kind] = trimmed
                keyStates[kind] = .saved
            } else {
                keyStates[kind] = .invalid(error.errorDescription ?? "Invalid key")
            }
        } catch {
            keyStates[kind] = .invalid(error.localizedDescription)
        }
    }

    // MARK: System

    var setupComplete: Bool {
        permissions.requiredGranted && hasKey(.openAI) && hotkeyRunning
    }

    func refreshPermissions() {
        let current = Permissions.current()
        if current != permissions { permissions = current }
    }

    func refreshDevices() {
        inputDevices = AudioDevices.inputDevices()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("myWhisperer: launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setStyle(_ style: CategoryStyle, for category: AppCategory) {
        preferences.styles[category] = style
    }

    func setRule(_ rule: AppRule) {
        if let index = preferences.appRules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
            preferences.appRules[index] = rule
        } else {
            preferences.appRules.append(rule)
        }
    }

    func removeRule(_ bundleID: String) {
        preferences.appRules.removeAll { $0.bundleID == bundleID }
    }

    /// Used by the URL scheme and snapshots to show HUD states.
    func previewPhase(_ phase: DictationPhase) {
        dictationPhaseChanged(phase)
    }

    func removePreviewKey(_ kind: APIKeyKind) {
        apiKeys[kind] = nil
        keyStates[kind] = .missing
    }

    /// Fills the model with realistic data for snapshots.
    func applyPreviewState() {
        permissions = PermissionsSnapshot(microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        hotkeyRunning = true
        apiKeys = [.openAI: "sk-preview-0000000000000000", .anthropic: "sk-ant-preview-000000000000"]
        keyStates = [.openAI: .valid, .anthropic: .valid]
        inputDevices = [
            AudioInputDevice(id: 1, uid: "builtin", name: "MacBook Pro Microphone", isBluetooth: false),
            AudioInputDevice(id: 2, uid: "airpods", name: "AirPods Pro", isBluetooth: true),
        ]
        dictionary = ["Kubernetes", "Ausländerbehörde", "Priya", "myWhisperer", "Anmeldung", "PostgreSQL", "Wispr"]
            .map { DictionaryEntry(term: $0) }
        snippets = [
            Snippet(trigger: "my calendar link", expansion: "https://cal.com/alex/30min"),
            Snippet(trigger: "my address", expansion: "Alex Example\nMusterstraße 12\n10115 Berlin"),
            Snippet(trigger: "intro reply", expansion: "Thanks for reaching out! I'd love to chat — here's a link to grab time that works for you: https://cal.com/alex/30min"),
        ]
        let now = Date()
        func entry(_ minutesAgo: Double, _ app: String, _ bundle: String, _ category: AppCategory, _ raw: String,
                   _ final: String, _ seconds: Double, status: DeliveryStatus = .inserted, mode: DictationMode = .dictate) -> HistoryEntry {
            HistoryEntry(date: now.addingTimeInterval(-minutesAgo * 60), mode: mode, appName: app, bundleID: bundle,
                         category: category, rawText: raw, finalText: final, audioSeconds: seconds,
                         timings: StageTimings(transcribeMs: 610, refineMs: 420, totalMs: 1080),
                         transcriptionModel: "gpt-transcribe", refinerModel: status == .failed ? nil : "claude-haiku-4-5",
                         refinerNote: status == .failed ? "Network error: The Internet connection appears to be offline." : nil,
                         status: status, costUSD: status == .failed ? nil : 0.0021)
        }
        var ledger = UsageLedger()
        for day in 0..<24 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            let dictations = [14, 22, 9, 31, 18, 0, 5, 26, 19, 12][day % 10]
            for _ in 0..<dictations {
                ledger.record([
                    UsageSample(provider: .openAI, kind: .transcription, model: "gpt-transcribe", audioSeconds: 7),
                    UsageSample(provider: .anthropic, kind: .cleanup, model: "claude-haiku-4-5", inputTokens: 1_450, outputTokens: 45),
                ], on: date)
            }
        }
        usage = ledger
        history = [
            entry(2, "Slack", "com.tinyspeck.slackmacgap", .work,
                  "um hey team so the deploy is going out at 3 no wait 4 today",
                  "Hey team, the deploy is going out at 4 today.", 4.2),
            entry(18, "Mail", "com.apple.mail", .email,
                  "hi anna thanks for sending the antrag over I'll get it to the ausländerbehörde by friday best alex",
                  "Hi Anna,\n\nThanks for sending the Antrag over. I'll get it to the Ausländerbehörde by Friday.\n\nBest,\nAlex", 7.5),
            entry(45, "Cursor", "com.todesktop.230313mzl4w4u92", .code,
                  "rename the use effect hook in app dot tsx to use sync state",
                  "Rename the useEffect hook in App.tsx to useSyncState", 3.9),
            entry(95, "Messages", "com.apple.MobileSMS", .personal,
                  "on my way be there in like ten minutes", "on my way, be there in 10 minutes", 2.4),
            entry(180, "Notes", "com.apple.Notes", .other, "", "", 5.1, status: .failed),
            entry(60 * 26, "Notion", "notion.id", .other,
                  "things to pack one passport two chargers three the green jacket",
                  "Things to pack:\n1. Passport\n2. Chargers\n3. The green jacket", 5.8),
            entry(60 * 50, "Slack", "com.tinyspeck.slackmacgap", .work,
                  "make this sound more friendly", "Totally fair question! I'll dig into it this afternoon and get back to you.", 2.1,
                  mode: .command),
        ]
    }
}
