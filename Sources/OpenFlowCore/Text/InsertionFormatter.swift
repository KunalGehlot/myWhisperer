import Foundation

/// Final deterministic touch-ups based on the characters around the cursor.
public enum InsertionFormatter {
    /// - Parameters:
    ///   - text: The text about to be inserted.
    ///   - before: Text immediately before the cursor, if known.
    ///   - fixCapitalization: Adjust the first letter to the sentence position.
    ///     Only used for raw transcripts; the refiner already sees the context.
    public static func format(_ text: String, before: String?, fixCapitalization: Bool) -> String {
        var result = text
        guard !result.isEmpty else { return result }

        if fixCapitalization {
            result = adjustCapitalization(result, before: before)
        } else {
            // Models sometimes capitalize a continuation anyway; fix only the
            // unambiguous case of an ordinary word mid-sentence.
            result = lowercaseContinuation(result, before: before)
        }

        // Add a separating space when continuing right after a word or a
        // sentence, unless the insertion starts with punctuation.
        if let last = before?.last, needsLeadingSpace(after: last, first: result.first!) {
            result = " " + result
        }
        return result
    }

    static func needsLeadingSpace(after previous: Character, first: Character) -> Bool {
        if previous.isWhitespace || previous.isNewline { return false }
        if "([{\"'“‘/-@#".contains(previous) { return false }
        if first.isWhitespace || first.isNewline { return false }
        if ".,;:!?)]}…%".contains(first) { return false }
        return true
    }

    static func lowercaseContinuation(_ text: String, before: String?) -> String {
        guard let last = (before ?? "").trimmingCharacters(in: .whitespaces).last,
              last.isLetter || last.isNumber || last == "," else { return text }
        return adjustCapitalization(text, before: before)
    }

    static func adjustCapitalization(_ text: String, before: String?) -> String {
        let context = (before ?? "").trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first.isLetter else { return text }

        let startsSentence: Bool
        if let last = context.last {
            startsSentence = ".!?\n".contains(last) || context.hasSuffix("\n")
        } else {
            startsSentence = true
        }

        if startsSentence {
            return first.uppercased() + text.dropFirst()
        }

        // Mid-sentence: lowercase an ordinary capitalized word ("The" → "the")
        // but keep "I", acronyms ("API") and names we can't distinguish.
        let firstWord = text.prefix { $0.isLetter }
        let isOrdinaryWord = firstWord.count > 1
            && firstWord.dropFirst().allSatisfy(\.isLowercase)
            && commonSentenceStarters.contains(firstWord.lowercased())
        if isOrdinaryWord {
            return first.lowercased() + text.dropFirst()
        }
        return text
    }

    /// Words recognizers capitalize at the start of every clip that are almost
    /// never proper nouns.
    static let commonSentenceStarters: Set<String> = [
        "the", "a", "an", "and", "but", "or", "so", "because", "then", "also", "which",
        "that", "this", "these", "those", "it", "we", "you", "he", "she", "they", "my",
        "our", "your", "to", "for", "with", "in", "on", "at", "if", "when", "as", "is",
        "are", "was", "were", "not", "just", "maybe", "please", "thanks", "yes", "no",
        "und", "aber", "oder", "dann", "das", "der", "die", "wir", "ich",
    ]
}
