import AppKit
import MyWhispererCore
import SwiftUI

/// Colours taken from the app icon (#5644E6 → #753CEC).
enum Brand {
    static let accent = Color(red: 86 / 255, green: 68 / 255, blue: 230 / 255)
    static let accentDeep = Color(red: 117 / 255, green: 60 / 255, blue: 236 / 255)
    /// A contrasting blue for charts and secondary stats.
    static let accentSecondary = Color(red: 0.22, green: 0.56, blue: 1.0)
    static let command = Color(red: 0.74, green: 0.58, blue: 1.0)
    static let gradient = LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The app's mark: the icon's microphone on the brand gradient.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Brand.gradient)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: max(1, size / 64))
            }
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: size / 40, y: size / 80)
            }
            .frame(width: size, height: size)
            .shadow(color: Brand.accent.opacity(0.35), radius: size / 8, y: size / 20)
    }
}

/// A keyboard key, e.g. "fn" or "space".
struct KeyCap: View {
    var label: String
    var large = false

    var body: some View {
        Text(label)
            .font(.system(size: large ? 22 : 12, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, large ? 18 : 7)
            .frame(minWidth: large ? 64 : 24, minHeight: large ? 56 : 22)
            .background {
                RoundedRectangle(cornerRadius: large ? 10 : 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0, y: large ? 2 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: large ? 10 : 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct PaneHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold))
            if let subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var symbol: String
    var tint: Color = Brand.accent

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// The icon of an installed app, or a generic one.
struct AppIconImage: View {
    var bundleID: String?
    /// Shown as a symbol when the app isn't installed.
    var category: AppCategory = .other
    var size: CGFloat = 20

    var body: some View {
        if let image = Self.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: category.symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size * 0.9, height: size * 0.9)
                .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color.primary.opacity(0.07)))
                .frame(width: size, height: size)
        }
    }

    private static var cache: [String: NSImage?] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        let key = bundleID ?? ""
        if let cached = cache[key] { return cached }
        var image: NSImage?
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache[key] = image
        return image
    }
}

/// Horizontal bar meter for the mic test.
struct LevelMeter: View {
    var level: Float
    var segments = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { i in
                let threshold = Float(i) / Float(segments)
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > threshold ? color(for: i) : Color.primary.opacity(0.1))
                    .frame(height: 14)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func color(for index: Int) -> Color {
        let fraction = Double(index) / Double(segments)
        if fraction > 0.85 { return .orange }
        return Brand.accent.opacity(0.5 + fraction * 0.5)
    }
}

/// Wraps children onto multiple lines (dictionary chips, language chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Removable pill used for dictionary terms.
struct Chip: View {
    var text: String
    var onRemove: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 13))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.45)
                .help("Remove")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(hovering ? 0.09 : 0.06)))
        .onHover { hovering = $0 }
    }
}

extension HotkeyChoice {
    /// Instruction fragment, e.g. "Hold fn".
    var holdHint: String { "Hold \(keyCap)" }
}
