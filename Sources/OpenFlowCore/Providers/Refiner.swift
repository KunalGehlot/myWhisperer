import Foundation

public struct RefinerReply: Sendable, Equatable {
    /// The model's raw reply; callers parse `<output>` from it.
    public var text: String
    public var inputTokens: Int
    public var outputTokens: Int

    public init(text: String, inputTokens: Int = 0, outputTokens: Int = 0) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public protocol Refiner: Sendable {
    var modelID: String { get }
    var provider: UsageProvider { get }
    func complete(system: String, user: String) async throws -> RefinerReply
}

/// Anthropic Messages API over raw HTTP (there is no official Swift SDK).
public struct AnthropicRefiner: Refiner {
    public var apiKey: String
    public var modelID: String
    public var provider: UsageProvider { .anthropic }
    public var http: HTTPClient
    public var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public var timeout: TimeInterval = 15

    public init(apiKey: String, model: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.modelID = model
        self.http = http
    }

    public func complete(system: String, user: String) async throws -> RefinerReply {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(provider: "Anthropic") }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(model: modelID, system: system, user: user))

        let data = try await http.send(request, provider: "Anthropic")
        return try Self.parse(data)
    }

    static func body(model: String, system: String, user: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [["role": "user", "content": user]],
            // Generation can stop at the closing tag; the parser accepts that.
            "stop_sequences": ["</output>"],
        ]
        if model.hasPrefix("claude-haiku") {
            // Haiku runs without thinking unless asked, and accepts temperature.
            body["temperature"] = 0
        } else {
            // Sonnet 5 / Opus 5 think adaptively and reject sampling params;
            // low effort keeps latency acceptable for a formatting task.
            body["output_config"] = ["effort": "low"]
        }
        return body
    }

    static func parse(_ data: Data) throws -> RefinerReply {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        if json["stop_reason"] as? String == "refusal" { throw ProviderError.refused }
        guard let content = json["content"] as? [[String: Any]] else { throw ProviderError.invalidResponse }
        var text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        // The stop sequence is not included in the text; restore it so the
        // reply is well-formed for the parser and for debugging.
        if json["stop_reason"] as? String == "stop_sequence" {
            text += "</output>"
        }
        let usage = json["usage"] as? [String: Any] ?? [:]
        // Cache writes/reads are billed differently; counting them at the base
        // input rate keeps the estimate simple (we don't use caching today).
        let input = (usage["input_tokens"] as? Int ?? 0)
            + (usage["cache_creation_input_tokens"] as? Int ?? 0)
            + (usage["cache_read_input_tokens"] as? Int ?? 0)
        return RefinerReply(text: text, inputTokens: input, outputTokens: usage["output_tokens"] as? Int ?? 0)
    }
}

/// OpenAI Responses API.
public struct OpenAIRefiner: Refiner {
    public var apiKey: String
    public var modelID: String
    public var provider: UsageProvider { .openAI }
    public var http: HTTPClient
    public var endpoint = URL(string: "https://api.openai.com/v1/responses")!
    public var timeout: TimeInterval = 15

    public init(apiKey: String, model: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.modelID = model
        self.http = http
    }

    public func complete(system: String, user: String) async throws -> RefinerReply {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(provider: "OpenAI") }
        do {
            return try await send(system: system, user: user, withReasoning: true)
        } catch ProviderError.http(let status, let message)
            where status == 400 && message.lowercased().contains("reasoning") {
            // Non-reasoning models reject the reasoning parameter.
            return try await send(system: system, user: user, withReasoning: false)
        }
    }

    private func send(system: String, user: String, withReasoning: Bool) async throws -> RefinerReply {
        var body: [String: Any] = [
            "model": modelID,
            "instructions": system,
            "input": user,
            "max_output_tokens": 4096,
        ]
        if withReasoning {
            body["reasoning"] = ["effort": "none"]
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await http.send(request, provider: "OpenAI")
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> RefinerReply {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        let usage = json["usage"] as? [String: Any] ?? [:]
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        if let text = json["output_text"] as? String {
            return RefinerReply(text: text, inputTokens: input, outputTokens: output)
        }
        guard let items = json["output"] as? [[String: Any]] else { throw ProviderError.invalidResponse }
        var text = ""
        for item in items where item["type"] as? String == "message" {
            for part in item["content"] as? [[String: Any]] ?? [] {
                if part["type"] as? String == "refusal" { throw ProviderError.refused }
                if part["type"] as? String == "output_text", let t = part["text"] as? String {
                    text += t
                }
            }
        }
        return RefinerReply(text: text, inputTokens: input, outputTokens: output)
    }
}

/// Validates API keys with a cheap real request (used by onboarding/Settings).
public enum KeyValidator {
    public static func validateOpenAI(_ key: String, http: HTTPClient = HTTPClient()) async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!, timeoutInterval: 10)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        _ = try await http.send(request, provider: "OpenAI")
    }

    public static func validateAnthropic(_ key: String, http: HTTPClient = HTTPClient()) async throws {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!, timeoutInterval: 10)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        _ = try await http.send(request, provider: "Anthropic")
    }
}
