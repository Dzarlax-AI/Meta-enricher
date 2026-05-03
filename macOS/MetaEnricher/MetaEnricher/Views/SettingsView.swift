import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var cameraRootPath   = ""
    @State private var ollamaURL        = ""
    @State private var ollamaModel      = ""
    @State private var defaultCreator   = ""
    @State private var defaultCopyright = ""
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var ollamaReachable: Bool? = nil
    @State private var showModelPicker = false
    @State private var pullStates: [String: PullState] = [:]
    @State private var isOllamaSetupExpanded = false

    struct PullState {
        var progress: OllamaService.PullProgress = .init()
        var isPulling = false
        var error: String? = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 16)

            Divider()

            // Content
            Form {
                Section("Photo Library") {
                    LabeledContent("Camera Root") {
                        HStack {
                            Text(cameraRootPath.isEmpty ? "Not set" : cameraRootPath)
                                .foregroundStyle(cameraRootPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Browse…") { browseCameraRoot() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }

                Section("Ollama AI") {
                    LabeledContent("Server URL") {
                        HStack {
                            TextField("http://localhost:11434", text: $ollamaURL)
                                .textFieldStyle(.roundedBorder)

                            // Reachability indicator
                            if let reachable = ollamaReachable {
                                Image(systemName: reachable ? "circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(reachable ? .green : .red)
                                    .font(.caption)
                            }
                        }
                    }
                    .onChange(of: ollamaURL) { _, _ in ollamaReachable = nil }

                    LabeledContent("Model") {
                        HStack {
                            TextField("Model name", text: $ollamaModel)
                                .textFieldStyle(.roundedBorder)

                            Picker("", selection: $ollamaModel) {
                                if !availableModels.contains(ollamaModel) && !ollamaModel.isEmpty {
                                    Text(ollamaModel).tag(ollamaModel)
                                }
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 44)

                            Button {
                                Task { await fetchModels() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Refresh models list")
                        }
                    }

                    DisclosureGroup(isExpanded: $isOllamaSetupExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            SetupStep(number: "1", title: "Download & install Ollama", detail: "Go to ollama.com and download the macOS app. Open it — it runs in the menu bar.") {
                                Button("Open ollama.com") {
                                    NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            SetupStep(number: "2", title: "Make sure Ollama is running", detail: "You should see the llama icon  in your menu bar. If not — launch Ollama from Applications.") {
                                EmptyView()
                            }
                            SetupStep(number: "3", title: "Download a model below", detail: "Use the \"Pull\" buttons in the Recommended Models section. qwen2.5-vl is a good starting point (~5 GB).") {
                                EmptyView()
                            }
                            SetupStep(number: "4", title: "That's it!", detail: "The server URL stays at http://localhost:11434 by default. Click \"Use\" next to any downloaded model.") {
                                EmptyView()
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        Text("How to set up Ollama")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { isOllamaSetupExpanded.toggle() }
                    }
                }

                Section("Recommended Models") {
                    ForEach(recommendedModels, id: \.name) { model in
                        ModelRowView(
                            model: model,
                            installed: availableModels.contains(model.name),
                            state: pullStates[model.name] ?? PullState(),
                            onPull: { Task { await pullModel(model.name) } },
                            onSelect: { ollamaModel = model.name }
                        )
                    }
                }

                Section {
                    LabeledContent("Creator") {
                        TextField("Photographer name", text: $defaultCreator)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Copyright") {
                        TextField("© 2025 Your Name", text: $defaultCopyright)
                            .textFieldStyle(.roundedBorder)
                    }
                } header: {
                    Text("Metadata Defaults")
                } footer: {
                    Text("Creator and Copyright will be pre-filled for every photo. You can still override them individually in the photo inspector.")
                        .foregroundStyle(.secondary)
                }

                Section("Advanced") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thumbnail Cache")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Clears cached previews (~400 MB max)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Clear Cache") {
                            Task { await ThumbnailService.shared.purgeAll() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("Reset Onboarding") {
                        appState.hasCompletedOnboarding = false
                        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 4)

            Divider()

            // Footer buttons
            HStack {
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
        }
        .frame(width: 480)
        .onAppear { populateFields() }
    }

    // MARK: - Actions

    private func populateFields() {
        cameraRootPath   = appState.cameraRoot?.path ?? ""
        ollamaURL        = appState.ollamaURL
        ollamaModel      = appState.ollamaModel
        defaultCreator   = appState.defaultCreator
        defaultCopyright = appState.defaultCopyright
    }

    private func browseCameraRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories  = true
        panel.canChooseFiles        = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your photo library root folder"
        panel.prompt  = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            cameraRootPath = url.path
        }
    }

    private func save() {
        if !cameraRootPath.isEmpty {
            appState.cameraRoot = URL(filePath: cameraRootPath)
        }
        appState.ollamaURL        = ollamaURL
        appState.ollamaModel      = ollamaModel
        appState.defaultCreator   = defaultCreator
        appState.defaultCopyright = defaultCopyright

        UserDefaults.standard.set(ollamaURL,        forKey: "ollamaURL")
        UserDefaults.standard.set(ollamaModel,      forKey: "ollamaModel")
        UserDefaults.standard.set(defaultCreator,   forKey: "defaultCreator")
        UserDefaults.standard.set(defaultCopyright, forKey: "defaultCopyright")

        dismiss()
    }

    private func testConnection() async {
        let reachable = await OllamaService.shared.checkOllama(baseURL: ollamaURL)
        ollamaReachable = reachable
        if reachable { await fetchModels() }
    }

    private func fetchModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        availableModels = await OllamaService.shared.listModels(baseURL: ollamaURL)
    }

    private func pullModel(_ name: String) async {
        pullStates[name] = PullState(isPulling: true)
        do {
            try await OllamaService.shared.pullModel(name: name, baseURL: ollamaURL) { prog in
                Task { @MainActor in
                    // Full replacement — nested mutation of Dictionary @State doesn't trigger SwiftUI update
                    var state = pullStates[name] ?? PullState()
                    state.progress = prog
                    pullStates[name] = state
                }
            }
            var done = pullStates[name] ?? PullState()
            done.isPulling = false
            pullStates[name] = done
            await fetchModels()
        } catch {
            var failed = pullStates[name] ?? PullState()
            failed.isPulling = false
            failed.error = error.localizedDescription
            pullStates[name] = failed
        }
    }

    private let recommendedModels: [RecommendedModel] = [
        RecommendedModel(name: "qwen3-vl:8b",        size: "~6 GB",  description: "⭐ Recommended — fast, great quality"),
        RecommendedModel(name: "qwen3-vl:32b",       size: "~20 GB", description: "High quality, needs 24+ GB RAM"),
        RecommendedModel(name: "qwen3-vl:235b-cloud",size: "Cloud",  description: "Runs in Ollama Cloud — no download needed", isCloud: true),
        RecommendedModel(name: "llama3.2-vision:11b",size: "~8 GB",  description: "Meta's latest vision model"),
        RecommendedModel(name: "moondream",           size: "~1.7 GB",description: "Tiny & fast, lower quality"),
    ]
}

struct RecommendedModel {
    let name: String
    let size: String
    let description: String
    var isCloud: Bool = false
}

private struct ModelRowView: View {
    let model: RecommendedModel
    let installed: Bool
    let state: SettingsView.PullState
    let onPull: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.callout.weight(.medium))
                    Text(model.size)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.fill.tertiary, in: Capsule())
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if state.isPulling {
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if state.progress.fraction > 0 {
                                ProgressView(value: state.progress.fraction, total: 1.0)
                            } else {
                                ProgressView()
                            }
                        }
                        .progressViewStyle(.linear)
                        Text(pullStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                if let err = state.error {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if model.isCloud {
                Button("Use") { onSelect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Image(systemName: "cloud.fill")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else if installed && !state.isPulling {
                Button("Use") { onSelect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Select this model. First enrichment may be slow while Ollama loads it into memory.")
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if !state.isPulling {
                Button("Pull") { onPull() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20)
            }
        }
        .padding(.vertical, 2)
    }

    private var pullStatusText: String {
        let p = state.progress
        if p.total > 0 {
            let mb = p.completed / 1_000_000
            let total = p.total / 1_000_000
            return "\(mb) / \(total) MB"
        }
        return p.status
    }
}

// MARK: - Setup helpers

private struct SetupStep<Content: View>: View {
    let number: String
    let title: String
    let detail: String
    var detail2: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.appAmber, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let detail2 {
                    Text(detail2).font(.caption).foregroundStyle(.secondary)
                }
                content()
            }
        }
    }
}

private struct CodeLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5))
    }
}
