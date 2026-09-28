import Foundation

public enum UsageProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAI
    case anthropic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    /// Where the provider shows actual billing.
    public var dashboardURL: URL {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/usage")!
        case .anthropic: URL(string: "https://console.anthropic.com/")!
        }
    }
}

public enum UsageKind: String, Codable, Sendable {
    case transcription
    case cleanup

    public var title: String {
        switch self {
        case .transcription: "Speech recognition"
        case .cleanup: "Cleanup"
        }
    }
}

/// What one API request consumed, as reported by the provider.
public struct UsageSample: Codable, Equatable, Sendable {
    public var provider: UsageProvider
    public var kind: UsageKind
    public var model: String
    public var audioSeconds: Double
    public var inputTokens: Int
    public var outputTokens: Int

    public init(provider: UsageProvider, kind: UsageKind, model: String,
                audioSeconds: Double = 0, inputTokens: Int = 0, outputTokens: Int = 0) {
        self.provider = provider
        self.kind = kind
        self.model = model
        self.audioSeconds = audioSeconds
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    /// Estimated list-price cost in USD, or nil for a model without a known price.
    public var estimatedCost: Double? { Pricing.cost(of: self) }
}

/// Published list prices. Estimates only; providers bill the exact amounts.
public enum Pricing {
    /// When these prices were checked against the providers' pricing pages.
    public static let verifiedOn = "28 Sep 2026"

    /// USD per minute of audio.
    static let transcriptionPerMinute: [String: Double] = [
        "gpt-transcribe": 0.0045,
        "gpt-4o-transcribe": 0.006,
        "gpt-4o-mini-transcribe": 0.003,
        "whisper-1": 0.006,
    ]

    /// USD per million input / output tokens.
    static let tokenPrices: [String: (input: Double, output: Double)] = [
        "claude-haiku-4-5": (1, 5),
        "claude-sonnet-5": (2, 10),
        "claude-opus-5": (5, 25),
        "gpt-6-luna": (0.10, 0.50),
    ]

    public static func cost(of sample: UsageSample) -> Double? {
        switch sample.kind {
        case .transcription:
            guard let rate = transcriptionPerMinute[sample.model] else { return nil }
            return sample.audioSeconds / 60 * rate
        case .cleanup:
            guard let price = tokenPrices[sample.model] else { return nil }
            return Double(sample.inputTokens) / 1_000_000 * price.input
                + Double(sample.outputTokens) / 1_000_000 * price.output
        }
    }

    public static func isPriced(_ model: String) -> Bool {
        transcriptionPerMinute[model] != nil || tokenPrices[model] != nil
    }
}

/// Running totals for one provider/kind/model on one day.
public struct UsageTotals: Codable, Equatable, Sendable {
    public var requests = 0
    public var audioSeconds = 0.0
    public var inputTokens = 0
    public var outputTokens = 0
    public var cost = 0.0
    /// Requests whose model had no known price (their cost isn't in `cost`).
    public var unpricedRequests = 0

    public init() {}

    mutating func add(_ sample: UsageSample) {
        requests += 1
        audioSeconds += sample.audioSeconds
        inputTokens += sample.inputTokens
        outputTokens += sample.outputTokens
        if let c = sample.estimatedCost { cost += c } else { unpricedRequests += 1 }
    }

    mutating func add(_ other: UsageTotals) {
        requests += other.requests
        audioSeconds += other.audioSeconds
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cost += other.cost
        unpricedRequests += other.unpricedRequests
    }
}

/// Usage aggregated per day, kept independently of history so deleting
/// dictations doesn't erase what was spent.
public struct UsageLedger: Codable, Equatable, Sendable {
    /// "yyyy-MM-dd" → "provider|kind|model" → totals.
    public var days: [String: [String: UsageTotals]] = [:]

    public init() {}

    public struct Line: Identifiable, Equatable, Sendable {
        public var provider: UsageProvider
        public var kind: UsageKind
        public var model: String
        public var totals: UsageTotals
        public var id: String { "\(provider.rawValue)|\(kind.rawValue)|\(model)" }
    }

    public mutating func record(_ samples: [UsageSample], on date: Date = Date(), calendar: Calendar = .current) {
        guard !samples.isEmpty else { return }
        let day = Self.dayKey(date, calendar: calendar)
        var entries = days[day] ?? [:]
        for sample in samples {
            let key = "\(sample.provider.rawValue)|\(sample.kind.rawValue)|\(sample.model)"
            var totals = entries[key] ?? UsageTotals()
            totals.add(sample)
            entries[key] = totals
        }
        days[day] = entries
    }

    /// Per provider/kind/model totals since `start` (nil = all time).
    public func lines(since start: Date?, calendar: Calendar = .current) -> [Line] {
        let startKey = start.map { Self.dayKey($0, calendar: calendar) }
        var merged: [String: UsageTotals] = [:]
        for (day, entries) in days where startKey == nil || day >= startKey! {
            for (key, totals) in entries {
                var sum = merged[key] ?? UsageTotals()
                sum.add(totals)
                merged[key] = sum
            }
        }
        return merged.compactMap { key, totals in
            let parts = key.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, let provider = UsageProvider(rawValue: parts[0]),
                  let kind = UsageKind(rawValue: parts[1]) else { return nil }
            return Line(provider: provider, kind: kind, model: parts[2], totals: totals)
        }
        .sorted { ($0.provider.rawValue, $0.kind.rawValue, $0.model) < ($1.provider.rawValue, $1.kind.rawValue, $1.model) }
    }

    public func total(for provider: UsageProvider? = nil, since start: Date?, calendar: Calendar = .current) -> UsageTotals {
        var sum = UsageTotals()
        for line in lines(since: start, calendar: calendar) where provider == nil || line.provider == provider {
            sum.add(line.totals)
        }
        return sum
    }

    /// Estimated cost per provider for each of the last `count` days (oldest first).
    public func dailyCosts(days count: Int, now: Date = Date(), calendar: Calendar = .current) -> [(day: Date, provider: UsageProvider, cost: Double)] {
        var result: [(Date, UsageProvider, Double)] = []
        let today = calendar.startOfDay(for: now)
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let entries = days[Self.dayKey(day, calendar: calendar)] ?? [:]
            for provider in UsageProvider.allCases {
                let cost = entries.filter { $0.key.hasPrefix(provider.rawValue + "|") }.values.reduce(0) { $0 + $1.cost }
                result.append((day, provider, cost))
            }
        }
        return result
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public extension Double {
    /// "$0.42", "$0.003", "< $0.001".
    var usdString: String {
        if self == 0 { return "$0.00" }
        if self < 0.001 { return "< $0.001" }
        if self < 0.1 { return String(format: "$%.3f", self) }
        return String(format: "$%.2f", self)
    }
}
