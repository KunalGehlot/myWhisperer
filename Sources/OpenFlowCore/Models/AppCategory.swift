import Foundation

/// Broad kind of app the user is dictating into. Drives the writing style.
public enum AppCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case personal
    case work
    case email
    case code
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .personal: "Personal messages"
        case .work: "Work messages"
        case .email: "Email"
        case .code: "Code & terminals"
        case .other: "Everything else"
        }
    }

    public var examples: String {
        switch self {
        case .personal: "Messages, WhatsApp, Telegram, Signal"
        case .work: "Slack, Teams, Discord, Linear"
        case .email: "Mail, Outlook, Gmail, Superhuman"
        case .code: "Xcode, VS Code, Cursor, Terminal, GitHub"
        case .other: "Notes, Docs, Notion, browsers, everything else"
        }
    }

    public var symbolName: String {
        switch self {
        case .personal: "message.fill"
        case .work: "bubble.left.and.bubble.right.fill"
        case .email: "envelope.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "doc.text.fill"
        }
    }
}

/// Maps a bundle identifier and/or browser URL host to an `AppCategory`.
public enum AppClassifier {
    static let bundleCategories: [String: AppCategory] = [
        // Personal messaging
        "com.apple.MobileSMS": .personal,
        "net.whatsapp.WhatsApp": .personal,
        "desktop.WhatsApp": .personal,
        "ru.keepcoder.Telegram": .personal,
        "org.telegram.desktop": .personal,
        "org.whispersystems.signal-desktop": .personal,
        "com.facebook.archon": .personal,
        "com.facebook.archon.developerID": .personal,
        // Work messaging
        "com.tinyspeck.slackmacgap": .work,
        "com.microsoft.teams": .work,
        "com.microsoft.teams2": .work,
        "com.hnc.Discord": .work,
        "com.linear": .work,
        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.smartemail-Mac": .email,
        "com.superhuman.electron": .email,
        "com.mimestream.Mimestream": .email,
        "it.bloop.airmail2": .email,
        // Code & terminals
        "com.apple.dt.Xcode": .code,
        "com.microsoft.VSCode": .code,
        "com.microsoft.VSCodeInsiders": .code,
        "com.todesktop.230313mzl4w4u92": .code, // Cursor
        "com.exafunction.windsurf": .code,
        "dev.zed.Zed": .code,
        "com.sublimetext.4": .code,
        "com.panic.Nova": .code,
        "com.apple.Terminal": .code,
        "com.googlecode.iterm2": .code,
        "dev.warp.Warp-Stable": .code,
        "com.mitchellh.ghostty": .code,
        "net.kovidgoyal.kitty": .code,
        "io.alacritty": .code,
    ]

    static let bundlePrefixCategories: [(String, AppCategory)] = [
        ("com.jetbrains.", .code),
        ("com.google.android.studio", .code),
    ]

    static let hostCategories: [(String, AppCategory)] = [
        ("mail.google.com", .email),
        ("outlook.live.com", .email),
        ("outlook.office.com", .email),
        ("outlook.office365.com", .email),
        ("mail.proton.me", .email),
        ("app.fastmail.com", .email),
        ("web.whatsapp.com", .personal),
        ("web.telegram.org", .personal),
        ("messenger.com", .personal),
        ("app.slack.com", .work),
        ("teams.microsoft.com", .work),
        ("teams.live.com", .work),
        ("discord.com", .work),
        ("linear.app", .work),
        ("github.com", .code),
        ("gitlab.com", .code),
        ("bitbucket.org", .code),
        ("vscode.dev", .code),
        ("replit.com", .code),
        ("codesandbox.io", .code),
    ]

    public static func category(bundleID: String?, urlHost: String?) -> AppCategory {
        // A browser tab is more specific than the browser itself.
        if let host = urlHost?.lowercased() {
            for (suffix, category) in hostCategories where host == suffix || host.hasSuffix("." + suffix) {
                return category
            }
        }
        guard let bundleID else { return .other }
        if let category = bundleCategories[bundleID] { return category }
        for (prefix, category) in bundlePrefixCategories where bundleID.hasPrefix(prefix) {
            return category
        }
        return .other
    }

    /// Browsers whose frontmost tab URL is worth reading.
    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.mozilla.firefox",
        "app.zen-browser.zen",
    ]
}
