import Foundation

/// Replaces spoken snippet cues with their stored text. Runs after cleanup and
/// is deterministic: the LLM never decides whether a snippet fires.
public enum SnippetExpander {
    public static func expand(_ text: String, snippets: [Snippet]) -> String {
        var result = text
        // Longest triggers first so "my work email" wins over "my email".
        let ordered = snippets
            .filter { !$0.trigger.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }

        for snippet in ordered {
            let words = snippet.trigger
                .split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty else { continue }
            let phrase = words.joined(separator: "[\\s,]+")

            // The whole dictation is the cue (maybe with a trailing period the
            // cleanup added): replace everything, keeping no punctuation.
            let whole = "^\\s*\(phrase)\\s*[.!?]?\\s*$"
            if let regex = try? NSRegularExpression(pattern: whole, options: [.caseInsensitive]),
               regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) != nil {
                return snippet.expansion
            }

            // The cue appears inside a sentence.
            let inline = "(?<![\\p{L}\\p{N}])\(phrase)(?![\\p{L}\\p{N}])"
            if let regex = try? NSRegularExpression(pattern: inline, options: [.caseInsensitive]) {
                let template = NSRegularExpression.escapedTemplate(for: snippet.expansion)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: template
                )
            }
        }
        return result
    }
}
