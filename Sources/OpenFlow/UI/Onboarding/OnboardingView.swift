import OpenFlowCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, keys, microphone, hotkey, tryIt, done

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .permissions: "Permissions"
        case .keys: "API keys"
        case .microphone: "Microphone"
        case .hotkey: "Hotkey"
        case .tryIt: "Try it"
        case .done: "Done"
        }
    }
}

struct OnboardingView: View {
    let model: AppModel
    var onFinish: () -> Void
    @State private var step: OnboardingStep
    @State private var goingForward = true

    init(model: AppModel, initialStep: OnboardingStep = .welcome, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        ZStack {
            content
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // Pinned: however tall a step gets, Back/Continue stay on screen.
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .frame(width: 760, height: 560)
        .background(backgroundGradient)
        .tint(Brand.accent)
    }

    private var backgroundGradient: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Brand.accent.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .permissions: PermissionsStep(model: model)
        case .keys: KeysStep(model: model)
        case .microphone: MicrophoneStep(model: model)
        case .hotkey: HotkeyStep(model: model)
        case .tryIt: TryItStep(model: model)
        case .done: DoneStep(hotkey: model.preferences.hotkey)
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Back") { move(-1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Brand.accent : Color.primary.opacity(0.15))
                        .frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3), value: step)
            Spacer()
            primaryButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.bar)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { move(1) }.buttonStyle(PrimaryButtonStyle())
        case .permissions:
            Button(model.permissions.requiredGranted ? "Continue" : "Skip for now") { move(1) }
                .buttonStyle(PrimaryButtonStyle(prominent: model.permissions.requiredGranted))
        case .keys:
            Button(model.hasKey(.openAI) ? "Continue" : "Skip for now") { move(1) }
                .buttonStyle(PrimaryButtonStyle(prominent: model.hasKey(.openAI)))
        case .done:
            Button("Start Dictating") { onFinish() }.buttonStyle(PrimaryButtonStyle())
        default:
            Button("Continue") { move(1) }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private func move(_ delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        goingForward = delta > 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = next }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background {
                if prominent {
                    Capsule().fill(Brand.gradient)
                } else {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shared layout for each step: icon, title, subtitle, content.
struct StepLayout<Content: View>: View {
    var symbol: String?
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        // Centered when it fits; scrolls when a step grows (e.g. both key
        // fields open with an error message).
        ViewThatFits(in: .vertical) {
            stack
            ScrollView { stack.padding(.vertical, 8) }
        }
    }

    private var stack: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: Brand.accent.opacity(0.3), radius: 8, y: 3)
                    .padding(.bottom, 16)
            }
            Text(title).font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            content
                .frame(maxWidth: 520)
                .padding(.top, 22)
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Steps

struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AppMark(size: 96)
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
            Text("Talk. It types.")
                .font(.system(size: 38, weight: .bold))
            Text("\(AppInfo.name) turns your voice into clean, well-formatted text in any app — Slack, Mail, Notion, your code editor. Just hold a key and speak.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            HStack(spacing: 22) {
                feature("wand.and.stars", "Cleans up “um”s and\nself-corrections")
                feature("app.badge", "Adapts to the app\nyou're writing in")
                feature("globe", "Keeps mixed languages\nexactly as spoken")
            }
            .padding(.top, 14)
            Spacer()
        }
        .padding(40)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true } }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Brand.accent)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 150)
    }
}

struct PermissionsStep: View {
    let model: AppModel

    var body: some View {
        StepLayout(symbol: "lock.shield", title: "Two quick permissions",
                   subtitle: "\(AppInfo.name) needs these to hear you and type for you. Nothing is recorded unless you're holding the key.") {
            VStack(spacing: 10) {
                ForEach([PermissionKind.microphone, .accessibility], id: \.self) { kind in
                    Card(padding: 12) { PermissionRow(kind: kind, status: model.permissions[kind]) }
                }
                if model.permissions.accessibility == .granted && !model.hotkeyRunning {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            PermissionRow(kind: .inputMonitoring, status: model.permissions.inputMonitoring)
                            HStack {
                                Text("macOS sometimes needs a relaunch before the dictation key works.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Relaunch \(AppInfo.name)") { Permissions.relaunch() }.controlSize(.small)
                            }
                        }
                    }
                }
                if model.permissions.requiredGranted {
                    Label("All set", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: model.permissions)
        }
    }
}

struct KeysStep: View {
    let model: AppModel

    var body: some View {
        StepLayout(symbol: "key.fill", title: "Connect your AI providers",
                   subtitle: "Bring your own keys — you pay the providers directly, usually a few cents a day. Keys are stored in your Keychain.") {
            VStack(spacing: 10) {
                Card(padding: 14) {
                    APIKeyField(model: model, kind: .openAI, purpose: "Required · speech recognition (GPT Transcribe)")
                }
                Card(padding: 14) {
                    APIKeyField(model: model, kind: .anthropic, purpose: "Recommended · cleanup and formatting (Claude Haiku)")
                }
            }
        }
    }
}

struct MicrophoneStep: View {
    let model: AppModel
    @State private var heardSomething = false

    var body: some View {
        @Bindable var model = model
        StepLayout(symbol: "mic.fill", title: "Check your microphone",
                   subtitle: "Say something. The bars should move as you talk.") {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Microphone", selection: $model.preferences.inputDeviceUID) {
                        Text("System default").tag(String?.none)
                        ForEach(model.inputDevices) { Text($0.name).tag(Optional($0.uid)) }
                    }
                    LevelMeter(level: model.audioLevel, segments: 32)
                    HStack {
                        Image(systemName: heardSomething ? "checkmark.circle.fill" : "waveform")
                            .foregroundStyle(heardSomething ? .green : .secondary)
                        Text(heardSomething ? "Sounds good!" : (model.permissions.microphone == .granted ? "Listening…" : "Allow microphone access in the previous step first."))
                            .font(.system(size: 13))
                            .foregroundStyle(heardSomething ? .primary : .secondary)
                    }
                }
            }
        }
        .onAppear {
            model.refreshDevices()
            model.micMonitor?(true)
        }
        .onDisappear { model.micMonitor?(false) }
        .onChange(of: model.audioLevel) { _, level in
            if level > 0.35 { withAnimation { heardSomething = true } }
        }
        .onChange(of: model.preferences.inputDeviceUID) {
            heardSomething = false
            model.micMonitor?(false)
            model.micMonitor?(true)
        }
    }
}

struct HotkeyStep: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        StepLayout(symbol: "keyboard", title: "Pick your dictation key",
                   subtitle: "Hold it to talk, release to insert. Double-tap to keep listening hands-free.") {
            VStack(spacing: 14) {
                HotkeyPicker(selection: $model.preferences.hotkey)
                if model.preferences.hotkey == .fn {
                    Card(padding: 14) { GlobeKeyNote() }
                }
            }
        }
    }
}

struct TryItStep: View {
    let model: AppModel
    @State private var text = ""
    @State private var startCount = 0
    @FocusState private var focused: Bool

    var body: some View {
        let succeeded = model.history.count > startCount && model.history.first?.status != .failed
        StepLayout(symbol: nil, title: "Give it a try",
                   subtitle: "Click in the box, hold \(model.preferences.hotkey.keyCap), and say:") {
            VStack(spacing: 14) {
                Text("“So um I'm trying out \(AppInfo.name), it's pretty fast — no wait, it's really fast.”")
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.accent)
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(height: 140)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(focused ? Brand.accent : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 1))
                if succeeded {
                    Label("That's it — works in every app.", systemImage: "party.popper.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                } else if !model.setupComplete {
                    Label("Finish the permission and key steps first for this to work.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .animation(.spring(response: 0.35), value: succeeded)
        }
        .onAppear {
            startCount = model.history.count
            focused = true
        }
    }
}

struct DoneStep: View {
    var hotkey: HotkeyChoice

    var body: some View {
        StepLayout(symbol: "checkmark", title: "You're all set",
                   subtitle: "\(AppInfo.name) lives in your menu bar. A few things worth knowing:") {
            VStack(spacing: 10) {
                tip(keys: [hotkey.keyCap], text: "Hold to dictate anywhere")
                tip(keys: [hotkey.keyCap, hotkey.keyCap], text: "Double-tap for hands-free, press again to finish")
                tip(keys: ["esc"], text: "Cancel while listening")
                tip(keys: ["⇧", hotkey.keyCap], text: "Command mode: select text, say how to change it")
                tip(keys: ["⌃", "⌘", "V"], text: "Paste your last dictation again")
            }
        }
    }

    private func tip(keys: [String], text: String) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in KeyCap(label: key) }
            }
            .frame(width: 120, alignment: .trailing)
            Text(text).font(.system(size: 13))
            Spacer()
        }
    }
}
