import Foundation

/// What the HUD and menu bar show.
public enum DictationPhase: Equatable, Sendable {
    case idle
    case recording(mode: DictationMode, handsFree: Bool)
    case processing(mode: DictationMode)
    /// Text was delivered; `copied` means it's on the clipboard instead.
    case done(copied: Bool)
    /// Brief notice that nothing was heard.
    case nothingHeard
    case error(message: String, action: ErrorAction?)

    public var isActive: Bool {
        switch self {
        case .recording, .processing: true
        default: false
        }
    }
}

/// A fix the HUD can offer next to an error.
public enum ErrorAction: String, Equatable, Sendable {
    case openAPIKeys
    case openModels
    case openPermissions
}

public enum SoundCue: Sendable {
    case start
    case lock
    case stop
    case cancel
    case error
}

public enum InsertOutcome: Sendable {
    case inserted
    case copiedToClipboard
}

// MARK: - Dependencies (implemented by AppKit adapters, faked in tests)

@MainActor
public protocol AudioSource: AnyObject {
    func start() throws
    /// Stops recording and returns the captured clip.
    func stop() -> AudioClip
    func cancel()
}

@MainActor
public protocol ContextProvider: AnyObject {
    /// Cheap: just the frontmost app, used before recording starts.
    var frontmostBundleID: String? { get }
    /// Slower (Accessibility): the full context, captured once recording runs.
    func captureContext() -> AppContext
}

@MainActor
public protocol TextInserting: AnyObject {
    func insert(_ text: String) async -> InsertOutcome
}

@MainActor
public protocol DictationHost: AnyObject {
    var preferences: Preferences { get }
    var dictionaryTerms: [String] { get }
    var snippets: [Snippet] { get }
    /// Builds a pipeline with current keys and models. `useRefiner` is false
    /// for apps set to raw mode.
    func makePipeline(useRefiner: Bool) throws -> DictationPipeline
    func dictationPhaseChanged(_ phase: DictationPhase)
    func play(_ cue: SoundCue)
    /// Every dictation ends here, including failures (with their audio).
    func record(_ entry: HistoryEntry, failedAudio: AudioClip?)
    /// Billable requests, recorded even when the dictation is discarded.
    func recordUsage(_ samples: [UsageSample])
}

/// Hotkey-driven state machine: hold to talk, double-tap (or Space while
/// holding) for hands-free, Esc to cancel.
@MainActor
public final class DictationController {
    public private(set) var phase: DictationPhase = .idle {
        didSet { host?.dictationPhaseChanged(phase) }
    }

    /// Releases shorter than this count as taps, not dictations.
    public var tapThreshold: Duration = .milliseconds(300)
    /// A second press within this window after a tap starts hands-free mode.
    public var doubleTapWindow: Duration = .milliseconds(350)
    /// Recordings stop automatically after this long.
    public var maximumRecording: Duration = .seconds(600)
    /// How long "done"/"nothing heard" notices stay before returning to idle.
    public var noticeDuration: Duration = .milliseconds(900)
    public var errorDuration: Duration = .seconds(4)

    private let audio: AudioSource
    private let contextProvider: ContextProvider
    private let inserter: TextInserting
    private weak var host: DictationHost?
    private let now: () -> ContinuousClock.Instant

    private var pressStart: ContinuousClock.Instant?
    private var hotkeyHeld = false
    private var pendingTapTask: Task<Void, Never>?
    private var maxLengthTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var context: AppContext?
    private var mode: DictationMode = .dictate

    public init(
        audio: AudioSource,
        contextProvider: ContextProvider,
        inserter: TextInserting,
        host: DictationHost,
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.audio = audio
        self.contextProvider = contextProvider
        self.inserter = inserter
        self.host = host
        self.now = now
    }

    public var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    // MARK: Hotkey events

    public func hotkeyDown(mode requestedMode: DictationMode = .dictate) {
        hotkeyHeld = true
        switch phase {
        case .recording(let currentMode, let handsFree):
            if pendingTapTask != nil {
                // Second press right after a tap: keep listening hands-free.
                pendingTapTask?.cancel()
                pendingTapTask = nil
                phase = .recording(mode: currentMode, handsFree: true)
                host?.play(.lock)
            } else if handsFree {
                // Pressing again ends a hands-free session.
                finish()
            }
        case .processing:
            return
        default:
            startRecording(mode: requestedMode)
        }
    }

    public func hotkeyUp() {
        hotkeyHeld = false
        guard case .recording(let currentMode, let handsFree) = phase, !handsFree,
              let pressStart else { return }
        let held = now() - pressStart
        if held >= tapThreshold {
            finish()
            return
        }
        guard host?.preferences.handsFreeEnabled == true else {
            cancel(silently: true)
            return
        }
        // A quick tap: wait briefly for a second tap before discarding.
        pendingTapTask = Task { [weak self, doubleTapWindow] in
            try? await Task.sleep(for: doubleTapWindow)
            guard !Task.isCancelled, let self else { return }
            self.pendingTapTask = nil
            if case .recording(_, false) = self.phase {
                self.cancel(silently: true)
            }
        }
        _ = currentMode
    }

    /// Space pressed while the hotkey is held: lock into hands-free mode.
    /// Returns true when the key press was consumed.
    @discardableResult
    public func lockHandsFree() -> Bool {
        guard hotkeyHeld, case .recording(let currentMode, false) = phase else { return false }
        phase = .recording(mode: currentMode, handsFree: true)
        host?.play(.lock)
        return true
    }

    /// Shift pressed while recording switches to command mode.
    public func switchMode(to newMode: DictationMode) {
        guard case .recording(let currentMode, let handsFree) = phase, currentMode != newMode else { return }
        mode = newMode
        phase = .recording(mode: newMode, handsFree: handsFree)
    }

    /// Another key was pressed while the hotkey was held. Right after the
    /// press this is a keyboard shortcut (fn+←, ⌥+e), not a dictation.
    public func hotkeyInterrupted() {
        guard case .recording(_, false) = phase, let pressStart, now() - pressStart < tapThreshold else { return }
        cancel(silently: true)
    }

    /// Esc: abandon the current recording or processing.
    @discardableResult
    public func cancel(silently: Bool = false) -> Bool {
        switch phase {
        case .recording:
            clearTimers()
            audio.cancel()
            if !silently { host?.play(.cancel) }
            phase = .idle
            return true
        case .processing:
            processingTask?.cancel()
            processingTask = nil
            host?.play(.cancel)
            phase = .idle
            return true
        default:
            return false
        }
    }

    // MARK: Flow

    private func startRecording(mode requestedMode: DictationMode) {
        resetTask?.cancel()
        guard let host else { return }

        if host.preferences.rule(for: contextProvider.frontmostBundleID)?.mode == .disabled { return }

        // Microphone first so the first word isn't clipped, then feedback.
        do {
            try audio.start()
        } catch {
            host.play(.error)
            showError("Microphone unavailable", action: .openPermissions)
            return
        }
        mode = requestedMode
        pressStart = now()
        phase = .recording(mode: requestedMode, handsFree: false)
        host.play(.start)

        // The HUD never takes focus, so the context still describes the app
        // the user is typing in.
        context = contextProvider.captureContext()

        maxLengthTask = Task { [weak self, maximumRecording] in
            try? await Task.sleep(for: maximumRecording)
            guard !Task.isCancelled, let self, self.isRecording else { return }
            self.finish()
        }
    }

    private func finish() {
        clearTimers()
        let clip = audio.stop()
        let context = self.context ?? AppContext()
        let mode = self.mode
        guard let host else { return }
        host.play(.stop)
        phase = .processing(mode: mode)

        processingTask = Task { [weak self] in
            await self?.process(clip: clip, context: context, mode: mode, host: host)
        }
    }

    private func process(clip: AudioClip, context: AppContext, mode: DictationMode, host: DictationHost) async {
        let prefs = host.preferences
        let rule = prefs.rule(for: context.bundleID)
        let category = rule?.category ?? context.category
        let useRefiner = rule?.mode != .raw && prefs.refinerProvider != .none
        let sharedContext = prefs.useFieldContext || mode == .command ? context : context.withoutFieldText

        let job = DictationJob(
            mode: mode,
            clip: clip,
            context: sharedContext,
            category: category,
            style: prefs.style(for: category),
            dictionary: host.dictionaryTerms,
            snippets: host.snippets,
            languages: prefs.languages,
            refinerTimeout: prefs.refinerTimeout
        )

        let result: DictationResult
        do {
            let pipeline = try host.makePipeline(useRefiner: useRefiner || mode == .command)
            result = try await pipeline.run(job)
        } catch is CancellationError {
            return
        } catch let error as DictationError {
            guard !Task.isCancelled else { return }
            host.record(failedEntry(clip: clip, context: context, category: category, mode: mode,
                                    note: error.errorDescription), failedAudio: clip)
            host.play(.error)
            showError(error.shortDescription, action: Self.action(for: error.providerError))
            return
        } catch let error as ProviderError {
            guard !Task.isCancelled else { return }
            host.record(failedEntry(clip: clip, context: context, category: category, mode: mode,
                                    note: error.errorDescription), failedAudio: clip)
            host.play(.error)
            showError(error.shortDescription, action: Self.action(for: error))
            return
        } catch {
            guard !Task.isCancelled else { return }
            showError("Something went wrong", action: nil)
            return
        }
        host.recordUsage(result.usage)
        guard !Task.isCancelled else { return }

        if result.skipped != nil {
            phase = .nothingHeard
            scheduleReset(after: noticeDuration)
            return
        }

        let outcome = await inserter.insert(result.finalText)
        guard !Task.isCancelled else { return }

        host.record(
            HistoryEntry(
                mode: mode,
                appName: context.appName,
                bundleID: context.bundleID,
                category: category,
                rawText: result.rawText,
                finalText: result.finalText.trimmingCharacters(in: .whitespaces),
                audioSeconds: clip.duration,
                timings: result.timings,
                transcriptionModel: prefs.transcriptionModel,
                refinerModel: result.refinerModel,
                refinerNote: result.refinerNote,
                status: outcome == .inserted ? .inserted : .copied,
                costUSD: result.estimatedCost
            ),
            failedAudio: nil
        )
        phase = .done(copied: outcome == .copiedToClipboard)
        scheduleReset(after: outcome == .copiedToClipboard ? errorDuration : noticeDuration)
    }

    private func failedEntry(clip: AudioClip, context: AppContext, category: AppCategory,
                             mode: DictationMode, note: String?) -> HistoryEntry {
        HistoryEntry(
            mode: mode,
            appName: context.appName,
            bundleID: context.bundleID,
            category: category,
            rawText: "",
            finalText: "",
            audioSeconds: clip.duration,
            transcriptionModel: host?.preferences.transcriptionModel ?? "",
            refinerNote: note,
            status: .failed
        )
    }

    private func showError(_ message: String, action: ErrorAction?) {
        phase = .error(message: message, action: action)
        scheduleReset(after: errorDuration)
    }

    private func scheduleReset(after delay: Duration) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.phase.isActive else { return }
            self.phase = .idle
        }
    }

    private func clearTimers() {
        pendingTapTask?.cancel()
        pendingTapTask = nil
        maxLengthTask?.cancel()
        maxLengthTask = nil
    }

    static func action(for error: ProviderError?) -> ErrorAction? {
        switch error {
        case .missingAPIKey, .invalidAPIKey: .openAPIKeys
        case .http(let status, _) where status == 404: .openModels
        default: nil
        }
    }
}
