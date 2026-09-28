import Foundation

public enum TextStats {
    /// Average typing speed used to estimate time saved.
    public static let typingWordsPerMinute = 40.0

    public static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    public struct Summary: Equatable, Sendable {
        public var dictations: Int
        public var words: Int
        /// Words per minute of speaking time.
        public var wordsPerMinute: Int
        /// Minutes saved versus typing at `typingWordsPerMinute`.
        public var minutesSaved: Int
        /// Consecutive days (ending today or yesterday) with at least one dictation.
        public var dayStreak: Int
    }

    public static func summarize(_ entries: [HistoryEntry], now: Date = Date(), calendar: Calendar = .current) -> Summary {
        let words = entries.reduce(0) { $0 + $1.wordCount }
        let speakingSeconds = entries.reduce(0.0) { $0 + $1.audioSeconds }
        let wpm = speakingSeconds > 1 ? Int((Double(words) / (speakingSeconds / 60)).rounded()) : 0
        let typingMinutes = Double(words) / typingWordsPerMinute
        let saved = max(0, Int((typingMinutes - speakingSeconds / 60).rounded()))
        return Summary(
            dictations: entries.count,
            words: words,
            wordsPerMinute: wpm,
            minutesSaved: saved,
            dayStreak: streak(entries.map(\.date), now: now, calendar: calendar)
        )
    }

    static func streak(_ dates: [Date], now: Date, calendar: Calendar) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: now)
        // Today without a dictation yet doesn't break the streak.
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
