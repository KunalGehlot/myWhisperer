import Foundation

/// Single source of truth for the product's identity.
public enum AppInfo {
    public static let name = "myWhisperer"
    public static let bundleIdentifier = "com.mywhisperer.app"
    public static let repositoryURL = URL(string: "https://github.com/KunalGehlot/myWhisperer")!

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
