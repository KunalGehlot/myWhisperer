import Foundation
import OpenFlowCore

/// `OpenFlow --dictate-file <audio> [options]`
///
/// Runs speech-to-text → cleanup → post-processing on a file and prints the
/// result with per-stage latency. Uses the app's saved preferences and keys
/// (Keychain, or OPENAI_API_KEY / ANTHROPIC_API_KEY).
///
/// Options:
///   --app <bundle id>        Pretend to dictate into this app (sets the style)
///   --before <text>          Text before the cursor
///   --selected <text>        Selected text (with --command)
///   --command                Command mode: the audio is an instruction
///   --raw                    Skip cleanup
///   --stt <model>            Override the transcription model
///   --refiner <model>        Override the cleanup model (claude-* or gpt-*)
///   --languages en,de        Override expected languages ("" = auto)
///   --json                   Machine-readable output
enum PipelineCLI {
    static func run(_ arguments: [String]) -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task.detached {
            box.code = await runAsync(arguments)
            semaphore.signal()
        }
        semaphore.wait()
        return box.code
    }

    private final class ResultBox: @unchecked Sendable { var code: Int32 = 0 }

    private static func value(_ flag: String, in arguments: [String]) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    private static func runAsync(_ arguments: [String]) async -> Int32 {
        guard let path = value("--dictate-file", in: arguments) else {
            print("usage: OpenFlow --dictate-file <audio> [--app id] [--before text] [--command] [--raw] [--stt m] [--refiner m] [--languages en,de] [--json]")
            return 2
        }
        guard let clip = loadClip(path) else {
            print("error: couldn't read audio at \(path)")
            return 1
        }

        var prefs = JSONFileStore<Preferences>(filename: "preferences.json").load() ?? Preferences()
        if let stt = value("--stt", in: arguments) { prefs.transcriptionModel = stt }
        if let languages = value("--languages", in: arguments) {
            prefs.languages = languages.split(separator: ",").map(String.init)
        }
        let dictionary = (JSONFileStore<[DictionaryEntry]>(filename: "dictionary.json").load() ?? []).map(\.term)
        let snippets = JSONFileStore<[Snippet]>(filename: "snippets.json").load() ?? []

        guard let openAIKey = Keychain.apiKey(.openAI, preferEnvironment: true) else {
            print("error: no OpenAI key (Keychain or OPENAI_API_KEY)")
            return 1
        }
        let transcriber = OpenAITranscriber(apiKey: openAIKey, model: prefs.transcriptionModel)

        var refiner: (any Refiner)?
        if !arguments.contains("--raw") {
            let model = value("--refiner", in: arguments) ?? prefs.refinerModel
            if model.hasPrefix("claude") {
                guard let key = Keychain.apiKey(.anthropic, preferEnvironment: true) else {
                    print("error: no Anthropic key (Keychain or ANTHROPIC_API_KEY)")
                    return 1
                }
                refiner = AnthropicRefiner(apiKey: key, model: model)
            } else if !model.isEmpty {
                refiner = OpenAIRefiner(apiKey: openAIKey, model: model)
            }
        }

        let bundleID = value("--app", in: arguments)
        let context = AppContext(
            bundleID: bundleID,
            appName: bundleID.map { $0.split(separator: ".").last.map(String.init) ?? $0 },
            textBeforeCursor: value("--before", in: arguments) ?? "",
            selectedText: value("--selected", in: arguments)
        )
        let category = prefs.rule(for: bundleID)?.category ?? context.category
        let mode: DictationMode = arguments.contains("--command") ? .command : .dictate
        let job = DictationJob(mode: mode, clip: clip, context: context, category: category,
                               style: prefs.style(for: category), dictionary: dictionary, snippets: snippets,
                               languages: prefs.languages, refinerTimeout: 30)
        let pipeline = DictationPipeline(transcriber: transcriber, transcriptionModel: prefs.transcriptionModel, refiner: refiner)

        do {
            let result = try await pipeline.run(job)
            if arguments.contains("--json") {
                let json: [String: Any] = [
                    "raw": result.rawText, "final": result.finalText,
                    "transcribeMs": result.timings.transcribeMs ?? -1, "refineMs": result.timings.refineMs ?? -1,
                    "totalMs": result.timings.totalMs ?? -1, "sttModel": prefs.transcriptionModel,
                    "refinerModel": result.refinerModel ?? "", "note": result.refinerNote ?? "",
                    "skipped": result.skipped.map { "\($0)" } ?? "", "category": category.rawValue,
                    "audioSeconds": clip.duration, "costUSD": result.estimatedCost ?? -1,
                ]
                let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                print("audio     \(String(format: "%.1f", clip.duration)) s · category \(category.rawValue) · \(prefs.transcriptionModel) → \(result.refinerModel ?? "no cleanup")")
                if let skipped = result.skipped { print("skipped   \(skipped)") }
                print("raw       \(result.rawText)")
                print("final     \(result.finalText)")
                if let note = result.refinerNote { print("note      \(note)") }
                print("timing    stt \(result.timings.transcribeMs ?? -1) ms · cleanup \(result.timings.refineMs ?? -1) ms · total \(result.timings.totalMs ?? -1) ms")
                print("cost      \(result.estimatedCost.map(\.usdString) ?? "unknown") (estimate)")
            }
            return 0
        } catch {
            print("error: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            return 1
        }
    }

    /// Reads WAV directly; converts anything else with afconvert.
    private static func loadClip(_ path: String) -> AudioClip? {
        let url = URL(fileURLWithPath: path)
        if let data = try? Data(contentsOf: url), let clip = AudioClip(wav: data) { return clip }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("openflow-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temp) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", path, temp.path]
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: temp) else { return nil }
        return AudioClip(wav: data)
    }
}
