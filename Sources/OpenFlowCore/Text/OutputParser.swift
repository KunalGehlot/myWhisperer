import Foundation

public enum OutputParser {
    /// Extracts the text between `<output>` and `</output>`.
    ///
    /// Returns nil when the model didn't use the tags (or refused), so the
    /// caller falls back to the raw transcript instead of inserting a preamble.
    /// A missing closing tag is accepted because we stop generation on it.
    public static func extract(_ response: String) -> String? {
        guard let open = response.range(of: "<output>") else { return nil }
        var body = response[open.upperBound...]
        if let close = body.range(of: "</output>") {
            body = body[..<close.lowerBound]
        }
        return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
