import OpenFlowCore
import SwiftUI

struct MainView: View {
    let model: AppModel
    @Bindable var navigation: Navigation

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { navigation.pane }, set: { if let p = $0 { navigation.pane = p } })) {
                Section {
                    ForEach(Pane.library) { pane in
                        Label(pane.title, systemImage: pane.symbol).tag(pane)
                    }
                }
                Section("Settings") {
                    ForEach(Pane.settings) { pane in
                        Label(pane.title, systemImage: pane.symbol).tag(pane)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) {
                SidebarStatus(model: model) { navigation.pane = $0 }
                    .padding(10)
            }
        } detail: {
            detail
                .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(Brand.accent)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.pane {
        case .home: HomeView(model: model) { navigation.pane = $0 }
        case .history: HistoryView(model: model)
        case .dictionary: DictionaryPane(model: model)
        case .snippets: SnippetsPane(model: model)
        case .styles: StylesPane(model: model)
        case .general: GeneralSettings(model: model)
        case .models: ModelSettings(model: model)
        case .usage: UsagePane(model: model)
        case .audio: AudioSettings(model: model)
        case .apps: AppRulesSettings(model: model)
        case .privacy: PrivacySettings(model: model)
        case .about: AboutPane()
        }
    }
}

/// Compact "is it working?" indicator at the bottom of the sidebar.
struct SidebarStatus: View {
    let model: AppModel
    var open: (Pane) -> Void

    var body: some View {
        let status = Self.status(model)
        Button {
            if let pane = status.pane { open(pane) }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.title).font(.system(size: 12, weight: .semibold))
                    Text(status.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(status.pane == nil)
    }

    struct Status {
        var title: String
        var detail: String
        var color: Color
        var pane: Pane?
    }

    static func status(_ model: AppModel) -> Status {
        if !model.permissions.requiredGranted {
            return Status(title: "Needs permissions", detail: "Click to grant access", color: .orange, pane: .privacy)
        }
        if !model.hasKey(.openAI) {
            return Status(title: "Add an API key", detail: "OpenAI key required", color: .orange, pane: .models)
        }
        if !model.hotkeyRunning {
            return Status(title: "Hotkey unavailable", detail: "Click to fix", color: .orange, pane: .privacy)
        }
        if model.isPaused {
            return Status(title: "Paused", detail: "Resume from the menu bar", color: .gray, pane: nil)
        }
        return Status(title: "Ready", detail: "\(model.preferences.hotkey.holdHint) to dictate", color: .green, pane: nil)
    }
}

// MARK: - Home

struct HomeView: View {
    let model: AppModel
    var open: (Pane) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: greeting, subtitle: "Talk naturally. \(AppInfo.name) writes it up wherever your cursor is.")

                if !model.setupComplete {
                    SetupCallout(model: model, open: open)
                }

                HowToCard(hotkey: model.preferences.hotkey)

                let stats = TextStats.summarize(model.history.filter { $0.status != .failed })
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    StatTile(value: stats.words.formatted(), label: "Words dictated", symbol: "text.word.spacing")
                    StatTile(value: stats.wordsPerMinute > 0 ? "\(stats.wordsPerMinute)" : "–", label: "Words per minute",
                             symbol: "speedometer", tint: Brand.accentSecondary)
                    StatTile(value: Self.duration(minutes: stats.minutesSaved), label: "Time saved",
                             symbol: "clock.badge.checkmark", tint: .green)
                    StatTile(value: "\(stats.dayStreak)", label: "Day streak", symbol: "flame.fill", tint: .orange)
                    Button { open(.usage) } label: {
                        StatTile(value: model.spentThisMonth.usdString, label: "Spent this month",
                                 symbol: "creditcard.fill", tint: .pink)
                    }
                    .buttonStyle(.plain)
                    .help("Estimated API costs — click for details")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent").font(.headline)
                        Spacer()
                        if !model.history.isEmpty {
                            Button("See all") { open(.history) }.buttonStyle(.link)
                        }
                    }
                    if model.history.isEmpty {
                        Card {
                            EmptyStateView(symbol: "waveform", title: "Nothing yet",
                                           message: "Your dictations will show up here, so nothing you say is ever lost.")
                        }
                    } else {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(model.history.prefix(5).enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider().padding(.leading, 48) }
                                    HistoryRow(model: model, entry: entry, compact: true)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours < 10 ? String(format: "%.1f h", hours) : "\(Int(hours)) h"
    }
}

struct SetupCallout: View {
    let model: AppModel
    var open: (Pane) -> Void

    var body: some View {
        let status = SidebarStatus.status(model)
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Almost ready — \(status.title.lowercased())").font(.system(size: 13, weight: .semibold))
                Text("Dictation starts working as soon as this is done.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.preferences.onboardingCompleted {
                Button("Fix now") { if let pane = status.pane { open(pane) } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Continue setup") { model.showOnboarding?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }
}

struct HowToCard: View {
    var hotkey: HotkeyChoice

    var body: some View {
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 0) {
                tip(keys: [hotkey.keyCap], title: "Hold to talk", detail: "Speak, then release. Text appears at your cursor.")
                Divider().padding(.horizontal, 16)
                tip(keys: [hotkey.keyCap, hotkey.keyCap], title: "Double-tap for hands-free",
                    detail: "Keeps listening. Press \(hotkey.keyCap) again to finish, esc to cancel.")
                Divider().padding(.horizontal, 16)
                tip(keys: ["⇧", hotkey.keyCap], title: "Command mode",
                    detail: "Select text and say what to change: “make this friendlier”.")
            }
        }
    }

    private func tip(keys: [String], title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in KeyCap(label: key) }
            }
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - History

struct HistoryView: View {
    let model: AppModel
    @State private var search = ""
    @State private var confirmClear = false

    var body: some View {
        let filtered = model.history.filter {
            search.isEmpty
                || $0.finalText.localizedCaseInsensitiveContains(search)
                || $0.rawText.localizedCaseInsensitiveContains(search)
                || ($0.appName ?? "").localizedCaseInsensitiveContains(search)
        }
        let groups = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    PaneHeader(title: "History", subtitle: "Every dictation, including ones that failed — retry them from here.")
                    if !model.history.isEmpty {
                        Button("Clear…", role: .destructive) { confirmClear = true }
                    }
                }
                if model.history.isEmpty {
                    Card { EmptyStateView(symbol: "clock", title: "No dictations yet", message: "Hold your hotkey anywhere and start talking.") }
                } else if filtered.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "No matches", message: "Nothing in your history matches “\(search)”.")
                }
                ForEach(groups, id: \.key) { day, entries in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.dayTitle(day)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider().padding(.leading, 48) }
                                    HistoryRow(model: model, entry: entry, compact: false)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search dictations")
        .confirmationDialog("Delete all history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { model.clearHistory() }
        } message: {
            Text("This removes every saved dictation and recording. It can't be undone.")
        }
    }

    static func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

struct HistoryRow: View {
    let model: AppModel
    let entry: HistoryEntry
    var compact: Bool
    @State private var expanded = false
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AppIconImage(bundleID: entry.bundleID, category: entry.category, size: 24)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.appName ?? "Unknown app").font(.system(size: 12, weight: .semibold))
                        if entry.mode == .command {
                            Badge(text: "Command", color: Brand.command)
                        }
                        switch entry.status {
                        case .failed: Badge(text: "Failed", color: .red)
                        case .copied: Badge(text: "Copied", color: .blue)
                        case .inserted: EmptyView()
                        }
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Text(entry.status == .failed && entry.finalText.isEmpty ? (entry.refinerNote ?? "Transcription failed") : displayText)
                        .font(.system(size: 13))
                        .foregroundStyle(entry.status == .failed && entry.finalText.isEmpty ? .secondary : .primary)
                        .lineLimit(expanded ? nil : (compact ? 2 : 3))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                actions
            }
            if expanded {
                details.padding(.leading, 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } }
    }

    /// Collapsed rows show paragraphs and list items on one flowing line.
    private var displayText: String {
        guard !expanded else { return entry.finalText }
        return entry.finalText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if entry.status == .failed, model.hasRecording(entry) {
                if model.retrying.contains(entry.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Retry") { model.retry(entry) }
                        .controlSize(.small)
                }
            }
            if !entry.finalText.isEmpty {
                Button {
                    TextInserter.copyToClipboard(entry.finalText)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                .help("Copy")
                .opacity(hovering || copied ? 1 : 0.35)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.rawText.isEmpty, entry.rawText != entry.finalText {
                VStack(alignment: .leading, spacing: 3) {
                    Text("What you said").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(entry.rawText).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            HStack(spacing: 14) {
                detail("waveform", "\(ModelCatalog.title(for: entry.transcriptionModel))")
                if let refiner = entry.refinerModel {
                    detail("sparkles", ModelCatalog.title(for: refiner))
                }
                detail("timer", String(format: "%.1fs audio", entry.audioSeconds))
                if let total = entry.timings.totalMs {
                    detail("bolt", "\(total) ms")
                }
                if let cost = entry.costUSD {
                    detail("creditcard", cost.usdString)
                }
            }
            if let note = entry.refinerNote, entry.status != .failed || !entry.finalText.isEmpty {
                Label(note, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Delete", role: .destructive) { model.deleteHistory([entry.id]) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
    }
}

struct Badge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.13)))
    }
}

// MARK: - Dictionary

struct DictionaryPane: View {
    let model: AppModel
    @State private var newTerm = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: "Dictionary",
                           subtitle: "Names, jargon, and words in other languages you want spelled exactly right. They're given to both the speech recognizer and the cleanup model.")
                HStack {
                    TextField("Add a word, name, or phrase…", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focused)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if model.dictionary.isEmpty {
                    Card {
                        EmptyStateView(symbol: "character.book.closed", title: "Your dictionary is empty",
                                       message: "Try adding your name, your team's product names, or German words you use often, like “Ausländerbehörde”.")
                    }
                } else {
                    Card {
                        FlowLayout(spacing: 8) {
                            ForEach(model.dictionary) { entry in
                                Chip(text: entry.term) { model.removeDictionaryTerm(entry) }
                            }
                        }
                    }
                    Text("\(model.dictionary.count) \(model.dictionary.count == 1 ? "entry" : "entries")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private func add() {
        // Allow pasting a comma- or newline-separated list.
        let terms = newTerm.split(whereSeparator: { $0 == "," || $0.isNewline })
        for term in terms { model.addDictionaryTerm(String(term)) }
        newTerm = ""
        focused = true
    }
}

// MARK: - Snippets

struct SnippetsPane: View {
    let model: AppModel
    @State private var editing: Snippet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    PaneHeader(title: "Snippets",
                               subtitle: "Say a short cue and \(AppInfo.name) types the full text: links, addresses, sign-offs, canned replies.")
                    Button {
                        editing = Snippet(trigger: "", expansion: "")
                    } label: {
                        Label("New Snippet", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if model.snippets.isEmpty {
                    Card {
                        EmptyStateView(symbol: "text.badge.plus", title: "No snippets yet",
                                       message: "Example: say “my calendar link” and get https://cal.com/you.")
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(model.snippets) { snippet in
                            SnippetCard(snippet: snippet) { editing = snippet }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet, isNew: !model.snippets.contains { $0.id == snippet.id }) { result in
                if let result { model.saveSnippet(result) }
                editing = nil
            } onDelete: {
                model.deleteSnippet(snippet)
                editing = nil
            }
        }
    }
}

struct SnippetCard: View {
    var snippet: Snippet
    var onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onEdit) {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "quote.opening").font(.system(size: 10)).foregroundStyle(Brand.accent)
                        Text(snippet.trigger).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    Text(snippet.expansion)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.accent.opacity(hovering ? 0.5 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SnippetEditor: View {
    @State var snippet: Snippet
    var isNew: Bool
    var onDone: (Snippet?) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Snippet" : "Edit Snippet").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("When I say").font(.system(size: 12, weight: .semibold))
                TextField("e.g. my calendar link", text: $snippet.trigger)
                    .textFieldStyle(.roundedBorder)
                Text("A short phrase you wouldn't say by accident.").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Type this").font(.system(size: 12, weight: .semibold))
                TextEditor(text: $snippet.expansion)
                    .font(.system(size: 13))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            }
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancel") { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { onDone(snippet) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(snippet.trigger.trimmingCharacters(in: .whitespaces).isEmpty
                              || snippet.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

// MARK: - Styles

struct StylesPane: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: "Styles",
                           subtitle: "\(AppInfo.name) matches your tone to the app you're writing in. Pick a style for each kind of app.")
                ForEach(AppCategory.allCases) { category in
                    StyleCard(model: model, category: category)
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }
}

struct StyleCard: View {
    let model: AppModel
    let category: AppCategory

    var body: some View {
        let style = model.preferences.style(for: category)
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title).font(.system(size: 14, weight: .semibold))
                        Text(category.examples).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Tone", selection: Binding(
                        get: { style.tone },
                        set: { model.setStyle(CategoryStyle(tone: $0, customInstructions: style.customInstructions), for: category) }
                    )) {
                        ForEach(Tone.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 270)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.tertiary)
                    Text(style.tone.example(for: category))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.default, value: style.tone)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))

                if category == .code {
                    Label("Identifiers, file names, and commands are always kept exactly as spoken.", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }

                TextField("Extra instructions (optional) — e.g. “Sign off with ‘Best, Alex’”",
                          text: Binding(
                            get: { style.customInstructions },
                            set: { model.setStyle(CategoryStyle(tone: style.tone, customInstructions: $0), for: category) }
                          ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }
        }
    }
}
