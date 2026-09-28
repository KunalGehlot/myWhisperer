import Foundation
import Security

public enum APIKeyKind: String, CaseIterable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"

    public var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    /// Environment variable honoured for development builds and the CLI.
    public var environmentVariable: String {
        switch self {
        case .openAI: "OPENAI_API_KEY"
        case .anthropic: "ANTHROPIC_API_KEY"
        }
    }

    public var consoleURL: URL {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }
}

/// API keys live in the login keychain, never in preference files.
public enum Keychain {
    static let service = AppInfo.bundleIdentifier

    public static func apiKey(_ kind: APIKeyKind, preferEnvironment: Bool = false) -> String? {
        let env = ProcessInfo.processInfo.environment[kind.environmentVariable].flatMap { $0.isEmpty ? nil : $0 }
        if preferEnvironment, let env { return env }
        if let stored = read(account: kind.rawValue), !stored.isEmpty { return stored }
        return env
    }

    @discardableResult
    public static func setAPIKey(_ value: String?, for kind: APIKeyKind) -> Bool {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        delete(account: kind.rawValue)
        guard !trimmed.isEmpty else { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
            kSecAttrLabel as String: "\(AppInfo.name) \(kind.title) API key",
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
