import Foundation

public enum ProviderError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey(provider: String)
    case invalidAPIKey(provider: String)
    case http(status: Int, message: String)
    case rateLimited
    case network(String)
    case timedOut
    case invalidResponse
    case refused

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider): "Add your \(provider) API key in Settings."
        case .invalidAPIKey(let provider): "Your \(provider) API key was rejected."
        case .http(let status, let message): "Request failed (\(status)): \(message)"
        case .rateLimited: "Rate limited by the provider. Try again in a moment."
        case .network(let message): "Network error: \(message)"
        case .timedOut: "The request timed out."
        case .invalidResponse: "Unexpected response from the provider."
        case .refused: "The model declined to process this text."
        }
    }

    /// Short text for the HUD.
    public var shortDescription: String {
        switch self {
        case .missingAPIKey: "Add an API key"
        case .invalidAPIKey: "API key rejected"
        case .http(let status, _): "Request failed (\(status))"
        case .rateLimited: "Rate limited"
        case .network: "No connection"
        case .timedOut: "Timed out"
        case .invalidResponse: "Bad response"
        case .refused: "Model declined"
        }
    }
}

/// Thin URLSession wrapper shared by providers.
public struct HTTPClient: Sendable {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest, provider: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderError.timedOut
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw ProviderError.invalidAPIKey(provider: provider)
        case 429:
            throw ProviderError.rateLimited
        default:
            throw ProviderError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    /// Pulls `error.message` out of an OpenAI/Anthropic error body.
    static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "unknown error"
    }
}

/// multipart/form-data body builder.
struct MultipartForm {
    let boundary = "myWhisperer-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    mutating func finish() -> Data {
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
