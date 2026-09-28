import OpenFlowCore
import SwiftUI

struct HUDView: View {
    let model: AppModel
    var onAction: (ErrorAction) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if model.phase != .idle {
                pill
                    .padding(.bottom, 14)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: HUDController.size.width, height: HUDController.size.height)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.78), value: phaseKey)
    }

    /// Changes only when the kind of content changes, so the level meter
    /// doesn't restart the spring animation 20 times a second.
    private var phaseKey: String {
        switch model.phase {
        case .idle: "idle"
        case .recording(let mode, let handsFree): "rec-\(mode)-\(handsFree)"
        case .processing: "processing"
        case .done(let copied): "done-\(copied)"
        case .nothingHeard: "nothing"
        case .error(let message, _): "error-\(message)"
        }
    }

    private var pill: some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.86))
                    .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            }
            .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
            .environment(\.colorScheme, .dark)
    }

    private var borderColor: Color {
        if case .recording(.command, _) = model.phase { return Brand.command.opacity(0.9) }
        return .white.opacity(0.14)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()

        case .recording(let mode, let handsFree):
            HStack(spacing: 10) {
                if mode == .command {
                    Label("Command", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.command)
                        .labelStyle(.titleAndIcon)
                }
                LiveWaveform(level: model.audioLevel, tint: mode == .command ? Brand.command : .white)
                if handsFree {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .help("Hands-free: press the hotkey again to finish")
                }
            }

        case .processing(let mode):
            HStack(spacing: 10) {
                ThinkingDots()
                if mode == .command {
                    Text("Applying…").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
            }

        case .done(let copied):
            if copied {
                Label("Copied — press ⌘V to paste", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: model.phase)
            }

        case .nothingHeard:
            Label("Didn't catch that", systemImage: "ear")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

        case .error(let message, let action):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let action {
                    Button("Fix") { onAction(action) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Brand.accent)
                }
            }
        }
    }
}

/// Bars that follow the live mic level, with a little per-bar variation so
/// it reads as a voice rather than a meter.
struct LiveWaveform: View {
    var level: Float
    var tint: Color = .white
    @State private var history: [CGFloat] = Array(repeating: 0, count: 11)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let weights: [CGFloat] = [0.45, 0.6, 0.8, 0.7, 0.95, 1, 0.9, 0.75, 0.85, 0.6, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(history.indices, id: \.self) { i in
                Capsule()
                    .fill(tint.opacity(0.55 + 0.45 * Double(history[i])))
                    .frame(width: 3, height: 4 + 18 * history[i] * Self.weights[i])
            }
        }
        .frame(height: 24)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: history)
        .onChange(of: level) { _, newValue in
            // Shift in the new level from the centre outwards.
            var next = history
            let value = CGFloat(newValue)
            let mid = next.count / 2
            for offset in stride(from: mid, to: 0, by: -1) {
                next[mid - offset] = next[mid - offset + 1]
                next[mid + offset] = next[mid + offset - 1]
            }
            next[mid] = value
            history = next
        }
    }
}

/// Three softly pulsing dots for "working on it".
struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin(t * 5 - Double(i) * 0.7)
                    Circle()
                        .fill(.white.opacity(reduceMotion ? 0.8 : 0.45 + 0.4 * (phase + 1) / 2))
                        .frame(width: 6, height: 6)
                        .offset(y: reduceMotion ? 0 : -2.5 * (phase + 1) / 2)
                }
            }
            .frame(height: 24)
        }
    }
}
