import Charts
import MyWhispererCore
import SwiftUI

struct UsagePane: View {
    let model: AppModel
    @State private var period: Period = .month

    enum Period: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .week: "7 days"
            case .month: "This month"
            case .all: "All time"
            }
        }

        var start: Date? {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .today: return calendar.startOfDay(for: now)
            case .week: return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
            case .month: return calendar.dateInterval(of: .month, for: now)?.start
            case .all: return nil
            }
        }
    }

    var body: some View {
        let lines = model.usage.lines(since: period.start)
        let total = model.usage.total(since: period.start)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    PaneHeader(title: "Usage & Costs",
                               subtitle: "Estimated from each request's reported usage and the providers' list prices (checked \(Pricing.verifiedOn)). Your provider dashboards show exact billing.")
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }

                HStack(spacing: 12) {
                    TotalCard(total: total, dictations: dictationCount)
                    ProviderCard(provider: .openAI, totals: model.usage.total(for: .openAI, since: period.start),
                                 hasKey: model.hasKey(.openAI))
                    ProviderCard(provider: .anthropic, totals: model.usage.total(for: .anthropic, since: period.start),
                                 hasKey: model.hasKey(.anthropic))
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily spend · last 30 days").font(.headline)
                        DailyChart(data: model.usage.dailyCosts(days: 30))
                            .frame(height: 170)
                    }
                }

                if lines.isEmpty {
                    Card {
                        EmptyStateView(symbol: "chart.bar", title: "No usage \(period == .all ? "yet" : "in this period")",
                                       message: "Each dictation's speech recognition and cleanup requests will be tallied here.")
                    }
                } else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            BreakdownHeader()
                            ForEach(lines) { line in
                                Divider()
                                BreakdownRow(line: line)
                            }
                        }
                    }
                }

                Text("A typical dictation (about 7 seconds) costs roughly \(typicalCost.usdString) with the current models.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private var dictationCount: Int {
        guard let start = period.start else { return model.history.count }
        return model.history.filter { $0.date >= start }.count
    }

    /// 7 s of speech plus a ~1.5k-token cleanup call.
    private var typicalCost: Double {
        let prefs = model.preferences
        var samples = [UsageSample(provider: .openAI, kind: .transcription, model: prefs.transcriptionModel, audioSeconds: 7)]
        if prefs.refinerProvider != .none {
            samples.append(UsageSample(provider: prefs.refinerProvider == .openAI ? .openAI : .anthropic, kind: .cleanup,
                                       model: prefs.refinerModel, inputTokens: 1_500, outputTokens: 50))
        }
        return samples.compactMap(\.estimatedCost).reduce(0, +)
    }
}

private struct TotalCard: View {
    let total: UsageTotals
    let dictations: Int

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Estimated total").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(total.cost.usdString)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(dictations) dictation\(dictations == 1 ? "" : "s") · \(total.requests) requests")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if total.unpricedRequests > 0 {
                    Label("\(total.unpricedRequests) request(s) used a model without a known price.", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProviderCard: View {
    let provider: UsageProvider
    let totals: UsageTotals
    let hasKey: Bool

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle().fill(color(for: provider)).frame(width: 8, height: 8)
                    Text(provider.title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Link(destination: provider.dashboardURL) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Open \(provider.title) billing dashboard")
                }
                Text(totals.cost.usdString)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var detail: String {
        if totals.requests == 0 { return hasKey ? "No requests yet" : "No key added" }
        var parts: [String] = []
        if totals.audioSeconds > 0 { parts.append(Self.minutes(totals.audioSeconds) + " of audio") }
        if totals.inputTokens + totals.outputTokens > 0 {
            parts.append("\(Self.tokens(totals.inputTokens)) in · \(Self.tokens(totals.outputTokens)) out")
        }
        return parts.joined(separator: "\n")
    }

    static func minutes(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds.rounded())) s" : String(format: "%.1f min", seconds / 60)
    }

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
            : n >= 1_000 ? String(format: "%.1fk", Double(n) / 1_000) : "\(n)"
    }
}

private struct DailyChart: View {
    let data: [(day: Date, provider: UsageProvider, cost: Double)]

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Cost", point.cost)
                )
                .foregroundStyle(by: .value("Provider", point.provider.title))
                .cornerRadius(2)
            }
        }
        .chartForegroundStyleScale([
            UsageProvider.openAI.title: color(for: .openAI),
            UsageProvider.anthropic.title: color(for: .anthropic),
        ])
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let cost = value.as(Double.self) { Text(cost.usdString) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
    }
}

private struct BreakdownHeader: View {
    var body: some View {
        HStack {
            Text("Model").frame(maxWidth: .infinity, alignment: .leading)
            Text("Used for").frame(width: 130, alignment: .leading)
            Text("Requests").frame(width: 70, alignment: .trailing)
            Text("Volume").frame(width: 130, alignment: .trailing)
            Text("Est. cost").frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct BreakdownRow: View {
    let line: UsageLedger.Line

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(color(for: line.provider)).frame(width: 7, height: 7)
                Text(ModelCatalog.title(for: line.model))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.kind.title).frame(width: 130, alignment: .leading).foregroundStyle(.secondary)
            Text("\(line.totals.requests)").frame(width: 70, alignment: .trailing).monospacedDigit()
            Text(volume).frame(width: 130, alignment: .trailing).foregroundStyle(.secondary).monospacedDigit()
            Text(Pricing.isPriced(line.model) ? line.totals.cost.usdString : "—")
                .frame(width: 80, alignment: .trailing).monospacedDigit()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var volume: String {
        switch line.kind {
        case .transcription: ProviderCard.minutes(line.totals.audioSeconds)
        case .cleanup: "\(ProviderCard.tokens(line.totals.inputTokens + line.totals.outputTokens)) tokens"
        }
    }
}

private func color(for provider: UsageProvider) -> Color {
    switch provider {
    case .openAI: Brand.accentSecondary
    case .anthropic: Color(red: 0.85, green: 0.47, blue: 0.34)
    }
}
