import AppKit
import MyWhispererCore

/// `mywhisperer://` URLs, used to drive the running app from scripts and tests:
///
///     open "mywhisperer://open?pane=history"
///     open "mywhisperer://onboarding"
///     open "mywhisperer://hud?state=recording"      (recording|command|processing|done|copied|nothing|error|idle)
///     open "mywhisperer://dictate?file=/path/clip.wav[&mode=command]"
///     open "mywhisperer://state"                     (writes state.json to the data folder)
@MainActor
final class URLRouter {
    private let model: AppModel
    private let windows: WindowManager
    private let controller: DictationController
    private let inserter: TextInserter
    private let contextCapture: ContextCapture

    init(model: AppModel, windows: WindowManager, controller: DictationController, inserter: TextInserter,
         contextCapture: ContextCapture) {
        self.model = model
        self.windows = windows
        self.controller = controller
        self.inserter = inserter
        self.contextCapture = contextCapture
    }

    func handle(_ url: URL) {
        guard url.scheme == "mywhisperer" else { return }
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })

        switch url.host {
        case "open":
            windows.showMain(pane: query["pane"].flatMap(Pane.init(rawValue:)))
        case "onboarding":
            windows.showOnboarding()
        case "hud":
            previewHUD(query["state"] ?? "recording")
        case "dictate":
            if let path = query["file"] {
                dictate(file: URL(fileURLWithPath: path), mode: query["mode"] == "command" ? .command : .dictate)
            }
        case "state":
            writeState()
        default:
            break
        }
    }

    private func previewHUD(_ state: String) {
        let phase: DictationPhase = switch state {
        case "command": .recording(mode: .command, handsFree: false)
        case "handsfree": .recording(mode: .dictate, handsFree: true)
        case "processing": .processing(mode: .dictate)
        case "done": .done(copied: false)
        case "copied": .done(copied: true)
        case "nothing": .nothingHeard
        case "error": .error(message: "Add an API key", action: .openAPIKeys)
        case "idle": .idle
        default: .recording(mode: .dictate, handsFree: false)
        }
        model.previewPhase(phase)
        if phase.isActive {
            // Animate the level meter so recording states look alive.
            Task {
                for i in 0..<60 {
                    model.audioLevel = Float(0.25 + 0.6 * abs(sin(Double(i) * 0.45)))
                    try? await Task.sleep(for: .milliseconds(60))
                }
                model.audioLevel = 0
                model.previewPhase(.idle)
            }
        }
    }

    /// Runs the real pipeline on an audio file as if it had just been spoken
    /// into the frontmost app, then inserts the result there.
    private func dictate(file: URL, mode: DictationMode) {
        guard let data = try? Data(contentsOf: file), let clip = AudioClip(wav: data) else {
            NSLog("myWhisperer: couldn't read WAV at \(file.path)")
            return
        }
        let context = contextCapture.captureContext()
        let prefs = model.preferences
        let category = prefs.rule(for: context.bundleID)?.category ?? context.category
        model.previewPhase(.processing(mode: mode))
        Task {
            do {
                let pipeline = try model.makePipeline(useRefiner: prefs.refinerProvider != .none)
                let result = try await pipeline.run(DictationJob(
                    mode: mode, clip: clip, context: context, category: category,
                    style: prefs.style(for: category), dictionary: model.dictionaryTerms,
                    snippets: model.snippets, languages: prefs.languages, refinerTimeout: prefs.refinerTimeout))
                model.recordUsage(result.usage)
                let outcome = await inserter.insert(result.finalText)
                model.record(HistoryEntry(
                    mode: mode, appName: context.appName, bundleID: context.bundleID, category: category,
                    rawText: result.rawText, finalText: result.finalText.trimmingCharacters(in: .whitespaces),
                    audioSeconds: clip.duration, timings: result.timings,
                    transcriptionModel: prefs.transcriptionModel, refinerModel: result.refinerModel,
                    refinerNote: result.refinerNote, status: outcome == .inserted ? .inserted : .copied,
                    costUSD: result.estimatedCost), failedAudio: nil)
                model.previewPhase(.done(copied: outcome == .copiedToClipboard))
            } catch {
                model.previewPhase(.error(message: (error as? DictationError)?.shortDescription ?? "Failed", action: nil))
            }
            try? await Task.sleep(for: .seconds(1))
            model.previewPhase(.idle)
        }
    }

    private func writeState() {
        let state: [String: Any] = [
            "phase": String(describing: model.phase),
            "permissions": [
                "microphone": String(describing: model.permissions.microphone),
                "accessibility": String(describing: model.permissions.accessibility),
                "inputMonitoring": String(describing: model.permissions.inputMonitoring),
            ],
            "hotkeyRunning": model.hotkeyRunning,
            "hotkeyNeedsRelaunch": model.hotkeyNeedsRelaunch,
            "keys": ["openAI": model.hasKey(.openAI), "anthropic": model.hasKey(.anthropic)],
            "historyCount": model.history.count,
            "spentThisMonthUSD": model.spentThisMonth,
            "lastEntry": model.history.first.map { ["app": $0.appName ?? "", "status": $0.status.rawValue,
                                                    "final": $0.finalText, "raw": $0.rawText,
                                                    "note": $0.refinerNote ?? "", "totalMs": $0.timings.totalMs ?? -1] } as Any,
            "lastContext": contextCapture.lastSummary,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: model.directory.appendingPathComponent("state.json"))
        }
    }
}
