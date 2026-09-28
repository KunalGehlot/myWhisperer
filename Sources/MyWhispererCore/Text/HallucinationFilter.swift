import Foundation

/// Drops text speech recognizers invent from silence or noise, such as the
/// subtitle credits Whisper-family models learned from video subtitles.
public enum HallucinationFilter {
    /// Phrases that are only ever hallucinations when they make up the whole
    /// transcript. Deliberately excludes things people really say ("thank you").
    static let wholeTranscriptPhrases: [String] = [
        "thank you for watching",
        "thanks for watching",
        "thank you so much for watching",
        "please subscribe",
        "like and subscribe",
        "subtitles by the amara.org community",
        "untertitel der amara.org-community",
        "untertitel im auftrag des zdf",
        "untertitel im auftrag des zdf, 2017",
        "untertitel im auftrag des zdf, 2018",
        "untertitel im auftrag des zdf, 2020",
        "untertitel im auftrag des zdf, 2021",
        "untertitelung des zdf, 2020",
        "sous-titres réalisés par la communauté d'amara.org",
        "copyright wdr 2021",
        "swr 2020",
    ]

    /// Substrings that never belong in dictation.
    static let creditMarkers: [String] = [
        "amara.org",
        "untertitel im auftrag",
        "untertitelung des",
        "subtitles by",
        "sous-titres réalisés",
    ]

    public static func clean(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(trimmed)
        if normalized.isEmpty { return "" }

        if wholeTranscriptPhrases.contains(where: { normalize($0) == normalized }) {
            return ""
        }

        // Drop sentences that are subtitle credits, keep the rest.
        let lower = trimmed.lowercased()
        if creditMarkers.contains(where: lower.contains) {
            let sentences = splitSentences(trimmed)
            let kept = sentences.filter { sentence in
                let s = sentence.lowercased()
                return !creditMarkers.contains(where: s.contains)
            }
            return kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // A single repeated character or pure punctuation ("...", "T T T").
        let letters = normalized.filter { !$0.isWhitespace }
        if Set(letters).count <= 1 { return "" }

        return trimmed
    }

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let kept = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "." || $0 == "-" || $0 == ","
        }
        return String(String.UnicodeScalarView(kept))
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,-"))
            .replacingOccurrences(of: "  ", with: " ")
    }

    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let sub { sentences.append(sub.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return sentences.isEmpty ? [text] : sentences
    }
}
