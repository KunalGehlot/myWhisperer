import Foundation

public struct Transcription: Sendable, Equatable {
    public var text: String
    public var usage: UsageSample?

    public init(text: String, usage: UsageSample? = nil) {
        self.text = text
        self.usage = usage
    }
}

public protocol Transcriber: Sendable {
    /// Returns the recognized text for a clip. `keywords` are terms to spell
    /// exactly (the user's dictionary).
    func transcribe(_ clip: AudioClip, prompt: String?, keywords: [String], languages: [String]) async throws -> Transcription
}

/// OpenAI `/v1/audio/transcriptions` (gpt-transcribe, whisper-1, gpt-4o-*).
public struct OpenAITranscriber: Transcriber {
    public var apiKey: String
    public var model: String
    public var http: HTTPClient
    public var endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    public var timeout: TimeInterval = 20

    public init(apiKey: String, model: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.model = model
        self.http = http
    }

    public func transcribe(_ clip: AudioClip, prompt: String?, keywords: [String], languages: [String]) async throws -> Transcription {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(provider: "OpenAI") }
        let wav = clip.wavData
        let json: [String: Any]
        do {
            json = try await send(wav, prompt: prompt, keywords: keywords, languages: languages)
        } catch ProviderError.http(let status, let message)
            where status == 400 && (message.lowercased().contains("language") || message.lowercased().contains("keyword")) {
            // A hint was rejected (e.g. an unsupported language code); plain
            // transcription beats failing the dictation.
            json = try await send(wav, prompt: prompt, keywords: [], languages: [])
        }
        guard let text = json["text"] as? String else { throw ProviderError.invalidResponse }
        return Transcription(text: text, usage: Self.usage(from: json, model: model, audioSeconds: clip.duration))
    }

    /// Billing is per minute of audio; token counts are kept when reported.
    static func usage(from json: [String: Any], model: String, audioSeconds: Double) -> UsageSample {
        var sample = UsageSample(provider: .openAI, kind: .transcription, model: model, audioSeconds: audioSeconds)
        if let usage = json["usage"] as? [String: Any] {
            if let seconds = usage["seconds"] as? Double { sample.audioSeconds = seconds }
            sample.inputTokens = usage["input_tokens"] as? Int ?? 0
            sample.outputTokens = usage["output_tokens"] as? Int ?? 0
        }
        return sample
    }

    private func send(_ wav: Data, prompt: String?, keywords: [String], languages: [String]) async throws -> [String: Any] {
        var form = MultipartForm()
        form.addFile("file", filename: "dictation.wav", mimeType: "audio/wav", data: wav)
        form.addField("model", model)
        form.addField("response_format", "json")
        if let prompt, !prompt.isEmpty {
            form.addField("prompt", prompt)
        }
        for field in Self.languageFields(model: model, languages: languages) {
            form.addField(field.name, field.value)
        }
        if ModelCatalog.keywordTranscriptionModels.contains(model) {
            for keyword in keywords.prefix(Self.maxKeywords) {
                form.addField("keywords[]", keyword)
            }
        }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finish()

        let data = try await http.send(request, provider: "OpenAI")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        return json
    }

    static let maxKeywords = 100

    /// Language hint fields for a model. Models with a `languages` list get all
    /// expected languages; single-language models only get a hint when exactly
    /// one language is expected (otherwise auto-detect handles code-switching).
    static func languageFields(model: String, languages: [String]) -> [(name: String, value: String)] {
        guard !languages.isEmpty else { return [] }
        if ModelCatalog.multiLanguageTranscriptionModels.contains(model) {
            return languages.map { ("languages[]", $0) }
        }
        if languages.count == 1 {
            return [("language", languages[0])]
        }
        return []
    }
}
