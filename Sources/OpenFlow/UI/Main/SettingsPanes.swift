import AppKit
import OpenFlowCore
import SwiftUI

/// Grouped form wrapper so every settings pane shares the same header.
struct SettingsPage<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 30)
                .padding(.top, 24)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - General

struct GeneralSettings: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        SettingsPage(title: "General") {
            Section("Dictation key") {
                HotkeyPicker(selection: $model.preferences.hotkey)
                if model.preferences.hotkey == .fn {
                    GlobeKeyNote()
                }
                Toggle(isOn: $model.preferences.handsFreeEnabled) {
                    Text("Double-tap for hands-free")
                    Text("Double-tap the key (or press space while holding it) to keep listening without holding.")
                }
                LabeledContent("Command mode") {
                    HStack(spacing: 4) { KeyCap(label: "⇧"); KeyCap(label: model.preferences.hotkey.keyCap) }
                }
                LabeledContent("Paste last transcript") {
                    HStack(spacing: 4) { KeyCap(label: "⌃"); KeyCap(label: "⌘"); KeyCap(label: "V") }
                }
            }

            Section("Feedback") {
                Toggle("Play sounds", isOn: $model.preferences.soundsEnabled)
                if model.preferences.soundsEnabled {
                    LabeledContent("Volume") {
                        HStack {
                            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                            Slider(value: $model.preferences.soundVolume, in: 0.05...1) { editing in
                                if !editing { model.play(.start) }
                            }
                            .frame(width: 180)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Behavior") {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Open at login")
                }
                Toggle(isOn: $model.preferences.restoreClipboard) {
                    Text("Restore clipboard after pasting")
                    Text("Text is inserted by pasting; your previous clipboard comes back right after.")
                }
            }

            Section {
                Button("Show Welcome Guide…") { model.showOnboarding?() }
            }
        }
    }
}

struct HotkeyPicker: View {
    @Binding var selection: HotkeyChoice

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HotkeyChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    VStack(spacing: 8) {
                        KeyCap(label: choice.keyCap)
                        Text(choice.title).font(.system(size: 11))
                            .foregroundStyle(selection == choice ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selection == choice ? Brand.accent.opacity(0.12) : Color.primary.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selection == choice ? Brand.accent : Color.primary.opacity(0.1), lineWidth: selection == choice ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct GlobeKeyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "globe").foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Set the 🌐 key to “Do Nothing”").font(.system(size: 12, weight: .semibold))
                Text("Otherwise macOS also opens the emoji picker or switches input source when you hold fn. System Settings → Keyboard → “Press 🌐 key to”.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Also check Keyboard → Dictation → Shortcut isn't “Press 🌐 twice”, or double-tapping fn for hands-free will start Apple Dictation too.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Models & keys

struct ModelSettings: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        SettingsPage(title: "Models & Keys",
                     subtitle: "Bring your own API keys. They're stored in your Mac's Keychain and only sent to their provider.") {
            Section {
                APIKeyField(model: model, kind: .openAI, purpose: "Required — turns your speech into text.")
                APIKeyField(model: model, kind: .anthropic, purpose: "Recommended — cleans up and formats what you said.")
            } header: {
                Text("API keys")
            }

            Section {
                Picker("Model", selection: $model.preferences.transcriptionModel) {
                    ForEach(ModelCatalog.transcriptionModels) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                if let option = ModelCatalog.transcriptionModels.first(where: { $0.id == model.preferences.transcriptionModel }) {
                    Text(option.detail).font(.caption).foregroundStyle(.secondary)
                }
                LanguagePicker(selection: $model.preferences.languages)
            } header: {
                Text("Speech recognition")
            } footer: {
                Text("Pick every language you speak, even just a few words of. Leave empty to auto-detect.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Provider", selection: Binding(
                    get: { model.preferences.refinerProvider },
                    set: { model.preferences.refinerProvider = $0 }
                )) {
                    ForEach(RefinerProvider.allCases) { Text($0.title).tag($0) }
                }
                if model.preferences.refinerProvider == .anthropic {
                    Picker("Model", selection: $model.preferences.anthropicModel) {
                        ForEach(ModelCatalog.anthropicModels) { Text($0.title).tag($0.id) }
                    }
                    modelDetail(ModelCatalog.anthropicModels, model.preferences.anthropicModel)
                    if !model.hasKey(.anthropic) {
                        Label("Add an Anthropic key above, or dictation will insert raw transcripts.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else if model.preferences.refinerProvider == .openAI {
                    Picker("Model", selection: $model.preferences.openAIRefinerModel) {
                        ForEach(ModelCatalog.openAIModels) { Text($0.title).tag($0.id) }
                    }
                    modelDetail(ModelCatalog.openAIModels, model.preferences.openAIRefinerModel)
                }
                if model.preferences.refinerProvider != .none {
                    LabeledContent("Wait for cleanup") {
                        HStack {
                            Slider(value: $model.preferences.refinerTimeout, in: 2...10, step: 1).frame(width: 160)
                            Text("\(Int(model.preferences.refinerTimeout)) s").monospacedDigit().frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Cleanup")
            } footer: {
                Text("Removes filler words, applies your corrections, adds punctuation and formatting, and matches the app's tone. If it takes longer than the wait time, the raw transcript is inserted instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func modelDetail(_ options: [ModelCatalog.Option], _ id: String) -> some View {
        Text(options.first { $0.id == id }?.detail ?? "")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct APIKeyField: View {
    let model: AppModel
    let kind: APIKeyKind
    var purpose: String
    @State private var draft = ""
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.system(size: 13, weight: .medium))
                    Text(purpose).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                status
            }
            if editing || !model.hasKey(kind) {
                HStack {
                    SecureField(kind == .openAI ? "sk-…" : "sk-ant-…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.keyStates[kind] == .checking)
                    if model.hasKey(kind) {
                        Button("Cancel") { editing = false; draft = "" }
                    }
                }
                Link("Get a \(kind.title) key →", destination: kind.consoleURL).font(.caption)
            } else {
                HStack {
                    Text(model.maskedKey(kind) ?? "Saved").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Change") { editing = true }
                    Button("Remove", role: .destructive) { Task { await model.setAPIKey("", for: kind) } }
                }
            }
            if case .invalid(let message) = model.keyStates[kind] {
                Label(message, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status: some View {
        switch model.keyStates[kind] ?? .missing {
        case .checking: ProgressView().controlSize(.small)
        case .valid, .saved: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .invalid: Label("Rejected", systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
        case .missing: Label("Not set", systemImage: "circle.dashed").foregroundStyle(.secondary).font(.caption)
        }
    }

    private func save() {
        let value = draft
        Task {
            await model.setAPIKey(value, for: kind)
            if model.keyStates[kind] == .valid || model.keyStates[kind] == .saved {
                draft = ""
                editing = false
            }
        }
    }
}

struct LanguagePicker: View {
    @Binding var selection: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Languages you speak").font(.system(size: 13))
            FlowLayout(spacing: 6) {
                ForEach(ModelCatalog.languages, id: \.code) { language in
                    let selected = selection.contains(language.code)
                    Button {
                        if selected {
                            selection.removeAll { $0 == language.code }
                        } else {
                            selection.append(language.code)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                            Text(language.name).font(.system(size: 12))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(Capsule().fill(selected ? Brand.accent : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Audio

struct AudioSettings: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        SettingsPage(title: "Microphone", subtitle: "Choose which microphone \(AppInfo.name) listens to.") {
            Section {
                Picker("Input", selection: $model.preferences.inputDeviceUID) {
                    Text("System default").tag(String?.none)
                    ForEach(model.inputDevices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
                LabeledContent("Level") {
                    LevelMeter(level: model.audioLevel).frame(width: 240)
                }
                Text("Speak to test — the bars should reach the middle when you talk normally.")
                    .font(.caption).foregroundStyle(.secondary)
                if selectedIsBluetooth {
                    Label("Bluetooth headsets switch to low-quality audio while their mic is in use. Your Mac's built-in microphone usually gives better results.",
                          systemImage: "headphones")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            model.refreshDevices()
            model.micMonitor?(true)
        }
        .onDisappear { model.micMonitor?(false) }
        .onChange(of: model.preferences.inputDeviceUID) {
            model.micMonitor?(false)
            model.micMonitor?(true)
        }
    }

    private var selectedIsBluetooth: Bool {
        let device = model.preferences.inputDeviceUID.flatMap { uid in model.inputDevices.first { $0.uid == uid } }
            ?? AudioDevices.defaultInputDevice()
        return device?.isBluetooth ?? false
    }
}

// MARK: - Apps

struct AppRulesSettings: View {
    let model: AppModel

    var body: some View {
        SettingsPage(title: "Apps",
                     subtitle: "Fine-tune \(AppInfo.name) per app: change its style category, insert raw text, or turn dictation off.") {
            Section {
                if model.preferences.appRules.isEmpty {
                    Text("No custom rules. Every app uses smart cleanup with its automatic style.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.preferences.appRules) { rule in
                    AppRuleRow(model: model, rule: rule)
                }
                Menu {
                    ForEach(Self.candidateApps(excluding: Set(model.preferences.appRules.map(\.bundleID))), id: \.bundleID) { app in
                        Button(app.name) {
                            model.setRule(AppRule(bundleID: app.bundleID, appName: app.name))
                        }
                    }
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } footer: {
                Text("The menu lists apps you've dictated into and apps that are running now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    struct Candidate { let bundleID: String; let name: String }

    static func candidateApps(excluding: Set<String>) -> [Candidate] {
        var seen = excluding
        var result: [Candidate] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, !seen.contains(id), id != AppInfo.bundleIdentifier else { continue }
            seen.insert(id)
            result.append(Candidate(bundleID: id, name: app.localizedName ?? id))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct AppRuleRow: View {
    let model: AppModel
    let rule: AppRule

    var body: some View {
        HStack(spacing: 10) {
            AppIconImage(bundleID: rule.bundleID, size: 22)
            Text(rule.appName)
            Spacer()
            Picker("Mode", selection: Binding(get: { rule.mode }, set: { var r = rule; r.mode = $0; model.setRule(r) })) {
                ForEach(AppRuleMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)
            Picker("Style", selection: Binding(get: { rule.category }, set: { var r = rule; r.category = $0; model.setRule(r) })) {
                Text("Automatic style").tag(AppCategory?.none)
                Divider()
                ForEach(AppCategory.allCases) { Text($0.title).tag(Optional($0)) }
            }
            .labelsHidden()
            .frame(width: 170)
            .disabled(rule.mode != .normal)
            Button {
                model.removeRule(rule.bundleID)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove rule")
        }
    }
}

// MARK: - Privacy & permissions

struct PrivacySettings: View {
    let model: AppModel
    @State private var confirmClear = false

    var body: some View {
        @Bindable var model = model
        SettingsPage(title: "Privacy & Permissions") {
            Section {
                ForEach([PermissionKind.microphone, .accessibility], id: \.self) { kind in
                    PermissionRow(kind: kind, status: model.permissions[kind])
                }
                if model.hotkeyNeedsRelaunch || (model.permissions.accessibility == .granted && !model.hotkeyRunning) {
                    PermissionRow(kind: .inputMonitoring, status: model.permissions.inputMonitoring)
                    HStack {
                        Label("The dictation key isn't responding yet. Relaunching usually fixes this after granting access.",
                              systemImage: "arrow.clockwise")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch") { Permissions.relaunch() }
                    }
                }
            } header: {
                Text("Permissions")
            }

            Section {
                Toggle(isOn: $model.preferences.useFieldContext) {
                    Text("Use the text around your cursor")
                    Text("Sends nearby text (never password fields) to the cleanup model so it can continue sentences, lists, and spelling correctly.")
                }
                Picker("Keep history", selection: $model.preferences.historyRetentionDays) {
                    Text("Forever").tag(Int?.none)
                    Text("30 days").tag(Optional(30))
                    Text("7 days").tag(Optional(7))
                    Text("1 day").tag(Optional(1))
                }
                .onChange(of: model.preferences.historyRetentionDays) { model.pruneHistory() }
                HStack {
                    Button("Show Data in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.directory]) }
                    Spacer()
                    Button("Delete All History…", role: .destructive) { confirmClear = true }
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Audio goes to OpenAI for transcription and text to your cleanup provider. Nothing is sent anywhere else, and history stays on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Delete all history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { model.clearHistory() }
        }
    }
}

struct PermissionRow: View {
    let kind: PermissionKind
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(status == .granted ? .green : Brand.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((status == .granted ? Color.green : Brand.accent).opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.system(size: 13, weight: .medium))
                Text(kind.explanation).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if status == .granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                // Accessibility never reports "not determined"; its first
                // request shows the system prompt, so it's still "Allow".
                Button(kind != .accessibility && status == .denied ? "Open Settings" : "Allow") {
                    Task { await Permissions.request(kind) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppMark(size: 84)
            Text(AppInfo.name).font(.system(size: 28, weight: .bold))
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            Text("Open-source voice dictation for macOS.\nSpeak naturally; get clean, well-formatted text in any app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link(destination: AppInfo.repositoryURL) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppInfo.repositoryURL.appendingPathComponent("issues")) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
            }
            .padding(.top, 6)
            Text("MIT License").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
