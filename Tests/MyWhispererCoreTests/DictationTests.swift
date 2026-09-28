import Foundation
import Testing
@testable import MyWhispererCore

// MARK: - Fakes

struct FakeTranscriber: Transcriber {
    var text: String = "um so we ship on friday"
    var error: ProviderError?
    let calls = Counter()

    func transcribe(_ clip: AudioClip, prompt: String?, keywords: [String], languages: [String]) async throws -> Transcription {
        calls.increment()
        if let error { throw error }
        return Transcription(text: text, usage: UsageSample(provider: .openAI, kind: .transcription,
                                                           model: "gpt-transcribe", audioSeconds: clip.duration))
    }
}

struct FakeRefiner: Refiner {
    var modelID = "claude-haiku-4-5"
    var provider: UsageProvider { .anthropic }
    var reply: String = "<output>So we ship on Friday.</output>"
    var delay: Duration = .zero
    var error: ProviderError?

    func complete(system: String, user: String) async throws -> RefinerReply {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return RefinerReply(text: reply, inputTokens: 1_000, outputTokens: 20)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

let speech = makeTone()
let silence = AudioClip(samples: Array(repeating: 0, count: 16_000))

// MARK: - Pipeline

@Suite struct DictationPipelineTests {
    @Test func cleansUpTranscript() async throws {
        let pipeline = DictationPipeline(transcriber: FakeTranscriber(), transcriptionModel: "t", refiner: FakeRefiner())
        let result = try await pipeline.run(DictationJob(clip: speech))
        #expect(result.rawText == "um so we ship on friday")
        #expect(result.finalText == "So we ship on Friday.")
        #expect(result.refinerModel == "claude-haiku-4-5")
        #expect(result.usage.map(\.kind) == [.transcription, .cleanup])
        // 1 s at $0.0045/min + 1000 in / 20 out tokens at $1/$5 per MTok.
        #expect(abs((result.estimatedCost ?? 0) - (0.0045 / 60 + 0.001 + 0.0001)) < 1e-9)
        #expect(result.skipped == nil)
        #expect(result.timings.transcribeMs != nil)
    }

    @Test func silenceNeverReachesTheProvider() async throws {
        let transcriber = FakeTranscriber()
        let pipeline = DictationPipeline(transcriber: transcriber, transcriptionModel: "t", refiner: FakeRefiner())
        let result = try await pipeline.run(DictationJob(clip: silence))
        #expect(result.skipped == .silent)
        #expect(transcriber.calls.count == 0)
    }

    @Test func hallucinationCountsAsNoSpeech() async throws {
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(text: "Thanks for watching!"), transcriptionModel: "t", refiner: FakeRefiner())
        #expect(try await pipeline.run(DictationJob(clip: speech)).skipped == .noSpeech)
    }

    @Test func slowRefinerFallsBackToRawText() async throws {
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(text: "we ship on friday"), transcriptionModel: "t",
            refiner: FakeRefiner(delay: .seconds(5)))
        let result = try await pipeline.run(DictationJob(clip: speech, refinerTimeout: 0.1))
        #expect(result.finalText == "We ship on friday")
        #expect(result.refinerModel == nil)
        #expect(result.refinerNote?.contains("timed out") == true)
    }

    @Test func malformedReplyFallsBackToRawText() async throws {
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(text: "hello world"), transcriptionModel: "t",
            refiner: FakeRefiner(reply: "Sure! Here's your text: Hello world."))
        let result = try await pipeline.run(DictationJob(clip: speech))
        #expect(result.finalText == "Hello world")
        #expect(result.refinerNote != nil)
    }

    @Test func emptyCleanupOfRealSpeechKeepsWords() async throws {
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(text: "please send the report today"), transcriptionModel: "t",
            refiner: FakeRefiner(reply: "<output></output>"))
        let result = try await pipeline.run(DictationJob(clip: speech))
        #expect(result.finalText == "Please send the report today")
    }

    @Test func expandsSnippetsAfterCleanup() async throws {
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(text: "my calendar link"), transcriptionModel: "t",
            refiner: FakeRefiner(reply: "<output>My calendar link.</output>"))
        let job = DictationJob(clip: speech, snippets: [Snippet(trigger: "my calendar link", expansion: "https://cal.com/k")])
        #expect(try await pipeline.run(job).finalText == "https://cal.com/k")
    }

    @Test func addsSpaceWhenContinuingText() async throws {
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(text: "and bread"), transcriptionModel: "t",
            refiner: FakeRefiner(reply: "<output>and bread.</output>"))
        let job = DictationJob(clip: speech, context: AppContext(textBeforeCursor: "We need milk"))
        #expect(try await pipeline.run(job).finalText == " and bread.")
    }

    @Test func commandModeRequiresRefiner() async {
        let pipeline = DictationPipeline(transcriber: FakeTranscriber(), transcriptionModel: "t", refiner: nil)
        await #expect(throws: DictationError.commandNeedsRefiner) {
            try await pipeline.run(DictationJob(mode: .command, clip: speech))
        }
    }

    @Test func transcriptionErrorsAreWrapped() async {
        let pipeline = DictationPipeline(
            transcriber: FakeTranscriber(error: .invalidAPIKey(provider: "OpenAI")), transcriptionModel: "t", refiner: nil)
        await #expect(throws: DictationError.transcriptionFailed(.invalidAPIKey(provider: "OpenAI"))) {
            try await pipeline.run(DictationJob(clip: speech))
        }
    }
}

// MARK: - Controller

@MainActor
final class FakeAudio: AudioSource {
    var clip = speech
    var started = 0
    var cancelled = 0
    var failStart = false
    func start() throws {
        if failStart { throw CancellationError() }
        started += 1
    }
    func stop() -> AudioClip { clip }
    func cancel() { cancelled += 1 }
}

@MainActor
final class FakeContext: ContextProvider {
    var context = AppContext(bundleID: "com.apple.mail", appName: "Mail", textBeforeCursor: "")
    var frontmostBundleID: String? { context.bundleID }
    func captureContext() -> AppContext { context }
}

@MainActor
final class FakeInserter: TextInserting {
    var inserted: [String] = []
    var outcome = InsertOutcome.inserted
    func insert(_ text: String) async -> InsertOutcome {
        inserted.append(text)
        return outcome
    }
}

@MainActor
final class FakeHost: DictationHost {
    var preferences = Preferences()
    var dictionaryTerms: [String] = []
    var snippets: [Snippet] = []
    var transcriber = FakeTranscriber()
    var refiner: (any Refiner)? = FakeRefiner()
    var phases: [DictationPhase] = []
    var cues: [SoundCue] = []
    var history: [HistoryEntry] = []
    var failedAudio: [AudioClip] = []
    var usedRefiner: Bool?
    var usage: [UsageSample] = []

    func makePipeline(useRefiner: Bool) throws -> DictationPipeline {
        usedRefiner = useRefiner
        return DictationPipeline(transcriber: transcriber, transcriptionModel: "t", refiner: useRefiner ? refiner : nil)
    }
    func dictationPhaseChanged(_ phase: DictationPhase) { phases.append(phase) }
    func play(_ cue: SoundCue) { cues.append(cue) }
    func recordUsage(_ samples: [UsageSample]) { usage += samples }
    func record(_ entry: HistoryEntry, failedAudio: AudioClip?) {
        history.append(entry)
        if let failedAudio { self.failedAudio.append(failedAudio) }
    }
}

@MainActor
final class Clock {
    var instant = ContinuousClock.now
    func advance(_ d: Duration) { instant = instant.advanced(by: d) }
}

@MainActor
@Suite struct DictationControllerTests {
    let audio = FakeAudio()
    let context = FakeContext()
    let inserter = FakeInserter()
    let host = FakeHost()
    let clock = Clock()

    func makeController() -> DictationController {
        let controller = DictationController(
            audio: audio, contextProvider: context, inserter: inserter, host: host, now: { [clock] in clock.instant })
        controller.doubleTapWindow = .milliseconds(40)
        controller.noticeDuration = .milliseconds(10)
        controller.errorDuration = .milliseconds(10)
        return controller
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func holdToTalkInsertsAndRecords() async {
        let controller = makeController()
        controller.hotkeyDown()
        #expect(controller.phase == .recording(mode: .dictate, handsFree: false))
        clock.advance(.seconds(2))
        controller.hotkeyUp()
        #expect(controller.phase == .processing(mode: .dictate))
        await waitUntil { !inserter.inserted.isEmpty }
        #expect(inserter.inserted == ["So we ship on Friday."])
        #expect(host.history.first?.status == .inserted)
        #expect(host.history.first?.appName == "Mail")
        #expect(host.history.first?.category == .email)
        #expect(host.cues == [.start, .stop])
        #expect(host.usage.count == 2)
        #expect((host.history.first?.costUSD ?? 0) > 0)
        await waitUntil { controller.phase == .idle }
        #expect(controller.phase == .idle)
    }

    @Test func quickTapIsDiscarded() async {
        let controller = makeController()
        controller.hotkeyDown()
        clock.advance(.milliseconds(100))
        controller.hotkeyUp()
        await waitUntil { controller.phase == .idle }
        #expect(controller.phase == .idle)
        #expect(audio.cancelled == 1)
        #expect(inserter.inserted.isEmpty)
    }

    @Test func doubleTapStartsHandsFreeAndNextPressFinishes() async {
        let controller = makeController()
        controller.hotkeyDown()
        clock.advance(.milliseconds(100))
        controller.hotkeyUp()
        controller.hotkeyDown()
        #expect(controller.phase == .recording(mode: .dictate, handsFree: true))
        controller.hotkeyUp()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(controller.phase == .recording(mode: .dictate, handsFree: true))
        #expect(audio.started == 1)
        controller.hotkeyDown()
        await waitUntil { !inserter.inserted.isEmpty }
        #expect(inserter.inserted.count == 1)
        #expect(host.cues.contains(.lock))
    }

    @Test func spaceWhileHoldingLocks() {
        let controller = makeController()
        #expect(controller.lockHandsFree() == false)
        controller.hotkeyDown()
        #expect(controller.lockHandsFree() == true)
        controller.hotkeyUp()
        #expect(controller.phase == .recording(mode: .dictate, handsFree: true))
    }

    @Test func escapeCancels() {
        let controller = makeController()
        controller.hotkeyDown()
        #expect(controller.cancel() == true)
        #expect(controller.phase == .idle)
        #expect(audio.cancelled == 1)
        #expect(host.cues.last == .cancel)
        #expect(controller.cancel() == false)
    }

    @Test func disabledAppIgnoresHotkey() {
        host.preferences.appRules = [AppRule(bundleID: "com.apple.mail", appName: "Mail", mode: .disabled)]
        let controller = makeController()
        controller.hotkeyDown()
        #expect(controller.phase == .idle)
        #expect(audio.started == 0)
    }

    @Test func rawAppSkipsRefiner() async {
        host.preferences.appRules = [AppRule(bundleID: "com.apple.mail", appName: "Mail", mode: .raw)]
        let controller = makeController()
        controller.hotkeyDown()
        clock.advance(.seconds(1))
        controller.hotkeyUp()
        await waitUntil { !inserter.inserted.isEmpty }
        #expect(host.usedRefiner == false)
        #expect(inserter.inserted == ["Um so we ship on friday"])
    }

    @Test func privacySettingStripsFieldText() async {
        host.preferences.useFieldContext = false
        context.context.textBeforeCursor = "secret draft"
        let controller = makeController()
        controller.hotkeyDown()
        clock.advance(.seconds(1))
        controller.hotkeyUp()
        await waitUntil { !inserter.inserted.isEmpty }
        // Without the field text there is no leading-space adjustment.
        #expect(inserter.inserted == ["So we ship on Friday."])
    }

    @Test func failureKeepsAudioAndShowsFix() async {
        host.transcriber = FakeTranscriber(error: .missingAPIKey(provider: "OpenAI"))
        let controller = makeController()
        controller.hotkeyDown()
        clock.advance(.seconds(1))
        controller.hotkeyUp()
        await waitUntil { !host.history.isEmpty }
        #expect(host.history.first?.status == .failed)
        #expect(host.failedAudio.count == 1)
        #expect(host.phases.contains(.error(message: "Add an API key", action: .openAPIKeys)))
    }

    @Test func clipboardFallbackIsReported() async {
        inserter.outcome = .copiedToClipboard
        let controller = makeController()
        controller.hotkeyDown()
        clock.advance(.seconds(1))
        controller.hotkeyUp()
        await waitUntil { !host.history.isEmpty }
        #expect(host.history.first?.status == .copied)
        #expect(host.phases.contains(.done(copied: true)))
    }

    @Test func silenceShowsNothingHeard() async {
        audio.clip = silence
        let controller = makeController()
        controller.hotkeyDown()
        clock.advance(.seconds(1))
        controller.hotkeyUp()
        await waitUntil { host.phases.contains(.nothingHeard) }
        #expect(host.phases.contains(.nothingHeard))
        #expect(inserter.inserted.isEmpty)
    }

    @Test func micFailureShowsError() {
        audio.failStart = true
        let controller = makeController()
        controller.hotkeyDown()
        #expect(controller.phase == .error(message: "Microphone unavailable", action: .openPermissions))
    }
}

@MainActor
@Suite struct DictationControllerModeTests {
    @Test func shiftSwitchesToCommandMode() {
        let host = FakeHost()
        let controller = DictationController(audio: FakeAudio(), contextProvider: FakeContext(), inserter: FakeInserter(), host: host)
        controller.hotkeyDown()
        controller.switchMode(to: .command)
        #expect(controller.phase == .recording(mode: .command, handsFree: false))
    }

    @Test func shortcutRightAfterPressCancels() {
        let clock = Clock()
        let audio = FakeAudio()
        let host = FakeHost() // the controller holds its host weakly
        let controller = DictationController(audio: audio, contextProvider: FakeContext(), inserter: FakeInserter(),
                                             host: host, now: { clock.instant })
        controller.hotkeyDown()
        clock.advance(.milliseconds(50))
        controller.hotkeyInterrupted()
        #expect(controller.phase == .idle)
        #expect(audio.cancelled == 1)
    }

    @Test func keyPressLateInDictationIsIgnored() {
        let clock = Clock()
        let host = FakeHost()
        let controller = DictationController(audio: FakeAudio(), contextProvider: FakeContext(), inserter: FakeInserter(),
                                             host: host, now: { clock.instant })
        controller.hotkeyDown()
        clock.advance(.seconds(2))
        controller.hotkeyInterrupted()
        #expect(controller.isRecording)
    }
}
