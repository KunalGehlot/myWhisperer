import Foundation

/// Tone preset for a category of apps.
public enum Tone: String, Codable, CaseIterable, Sendable, Identifiable {
    case formal
    case casual
    case veryCasual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .formal: "Formal"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        }
    }

    /// How the same dictation comes out in this tone, per kind of app.
    public func example(for category: AppCategory) -> String {
        switch (category, self) {
        case (.personal, .formal): "Hi Sam, are you free for dinner on Friday? Let me know."
        case (.personal, .casual): "Hey Sam, are you free for dinner Friday? Let me know!"
        case (.personal, .veryCasual): "hey sam free for dinner friday? lmk"
        case (.work, .formal): "Hi team, the release is moving to Thursday. I'll share the updated checklist today."
        case (.work, .casual): "Hey team, release is moving to Thursday. I'll share the updated checklist today."
        case (.work, .veryCasual): "hey team release moves to thursday, will share the checklist today"
        case (.email, .formal): "Hi Anna,\n\nThank you for the update. I'll review the contract and get back to you by Friday.\n\nBest regards,"
        case (.email, .casual): "Hi Anna,\n\nThanks for the update! I'll look over the contract and get back to you by Friday.\n\nBest,"
        case (.email, .veryCasual): "hey anna, thanks for the update! will look over the contract and get back to you by friday"
        case (.code, .formal): "Rename the fetchUser function in api/client.ts to loadUser and update its callers."
        case (.code, .casual): "Rename fetchUser in api/client.ts to loadUser and update the callers."
        case (.code, .veryCasual): "rename fetchUser in api/client.ts to loadUser, update callers"
        case (.other, .formal): "Meeting notes: we agreed to launch in March and hire two engineers."
        case (.other, .casual): "Meeting notes: we're launching in March and hiring two engineers."
        case (.other, .veryCasual): "meeting notes: launching in march, hiring two engineers"
        }
    }

    var instruction: String {
        switch self {
        case .formal:
            "Formal: complete sentences, standard capitalization and full punctuation. No slang; keep contractions only if the user said them."
        case .casual:
            "Casual: natural and conversational. Standard capitalization and punctuation, keep contractions, keep it concise."
        case .veryCasual:
            "Very casual: texting style. All lowercase except names and \"I\" may stay lowercase too, minimal punctuation, no period at the very end."
        }
    }
}

/// The user's style settings for one `AppCategory`.
public struct CategoryStyle: Codable, Equatable, Sendable {
    public var tone: Tone
    /// Free-form extra instructions, e.g. "Sign emails with 'Best, Alex'".
    public var customInstructions: String

    public init(tone: Tone, customInstructions: String = "") {
        self.tone = tone
        self.customInstructions = customInstructions
    }

    public static func defaultStyle(for category: AppCategory) -> CategoryStyle {
        switch category {
        case .personal: CategoryStyle(tone: .casual)
        case .work: CategoryStyle(tone: .casual)
        case .email: CategoryStyle(tone: .formal)
        case .code: CategoryStyle(tone: .casual)
        case .other: CategoryStyle(tone: .formal)
        }
    }
}
