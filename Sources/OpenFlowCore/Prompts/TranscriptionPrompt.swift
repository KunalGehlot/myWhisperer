import Foundation

/// Builds the `prompt` sent to the speech recognizer. Recognizers use it as
/// "previous text", so it biases spelling of names and jargon.
public enum TranscriptionPrompt {
    /// whisper-1 only reads the last ~224 tokens; ~700 characters stays safely
    /// under that for mixed-language text.
    public static let characterBudget = 700

    public static func make(dictionary: [String], textBeforeCursor: String?) -> String? {
        var budget = characterBudget
        var pieces: [String] = []

        // Dictionary terms first: they matter most for spelling.
        let terms = dictionary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !terms.isEmpty {
            var kept: [String] = []
            var used = "Vocabulary: ".count + 1
            for term in terms {
                let cost = term.count + 2
                if used + cost > budget { break }
                kept.append(term)
                used += cost
            }
            if !kept.isEmpty {
                let line = "Vocabulary: " + kept.joined(separator: ", ") + "."
                pieces.append(line)
                budget -= line.count + 1
            }
        }

        // Then the tail of what's already typed, so the recognizer continues
        // in the same language and register.
        if let before = textBeforeCursor?.trimmingCharacters(in: .whitespacesAndNewlines),
           !before.isEmpty, budget > 40 {
            pieces.append(String(before.suffix(budget)))
        }

        let prompt = pieces.joined(separator: "\n")
        return prompt.isEmpty ? nil : prompt
    }
}
