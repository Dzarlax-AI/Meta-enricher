import SwiftUI

struct ImportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var sdCards: [URL] = []
    @State private var selectedCard: URL? = nil
    @State private var destinationPath = ""
    @State private var selectedSchema: ImportSchema = .metaEnricher
    @State private var progress: ImportProgress? = nil
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Import from SD Card", systemImage: "sdcard")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if progress == nil || progress?.done == true {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 16)

            Divider()

            if let prog = progress, prog.done {
                doneState(prog)
            } else if isImporting, let prog = progress {
                importingState(prog)
            } else {
                setupState
            }
        }
        .frame(width: 520)
        .onAppear {
            scanForCards()
            if let root = appState.cameraRoot {
                destinationPath = root.path
                selectedSchema = ImportService.shared.detectSchema(in: root)
            }
        }
    }

    // MARK: - Setup State

    @ViewBuilder
    private var cardPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SD Card")
                .font(.headline)

            if sdCards.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Scanning for SD cards…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("SD Card", selection: $selectedCard) {
                    ForEach(sdCards, id: \.self) { card in
                        Text(card.lastPathComponent).tag(Optional(card))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Button("Refresh") { scanForCards() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var setupState: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardPickerSection
                .padding(.horizontal, 20)

            Divider()

            // Destination
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.headline)

                HStack {
                    TextField("Destination folder", text: $destinationPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") { browseDestination() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)

            // Schema picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Folder Structure")
                    .font(.headline)

                Picker("Schema", selection: $selectedSchema) {
                    ForEach(ImportSchema.allCases) { schema in
                        Text(schema.rawValue).tag(schema)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(selectedSchema.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)

            Spacer()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Import") {
                    Task { await startImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCard == nil || destinationPath.isEmpty)
            }
            .padding(20)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Importing State

    private func importingState(_ prog: ImportProgress) -> some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                ProgressView(value: prog.total > 0 ? Double(prog.copied) / Double(prog.total) : 0)
                    .progressViewStyle(.linear)

                HStack {
                    Text(prog.currentFile.isEmpty ? "Preparing…" : prog.currentFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(prog.copied) / \(prog.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let err = prog.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Cancel Import") {
                    importTask?.cancel()
                    isImporting = false
                    progress = nil
                }
                .foregroundStyle(.red)
            }
            .padding(20)
        }
    }

    // MARK: - Done State

    private func doneState(_ prog: ImportProgress) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: prog.error != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(prog.error != nil ? .orange : .green)

            Text(prog.error != nil ? "Import Completed with Warnings" : "Import Complete")
                .font(.title3)
                .fontWeight(.semibold)

            Text("\(prog.copied) of \(prog.total) files copied")
                .foregroundStyle(.secondary)

            if let err = prog.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Spacer()

            Divider()

            HStack {
                Button("Import More") {
                    progress = nil
                    isImporting = false
                    selectedCard = nil
                    scanForCards()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Done") {
                    Task { await appState.loadSessions() }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func scanForCards() {
        Task {
            let cards = await ImportService.shared.findSDCards()
            sdCards = cards
            if selectedCard == nil { selectedCard = cards.first }
        }
    }

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories  = true
        panel.canChooseFiles        = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose import destination folder"
        panel.prompt  = "Select"
        if let root = appState.cameraRoot {
            panel.directoryURL = root
        }
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
            selectedSchema = ImportService.shared.detectSchema(in: url)
        }
    }

    @MainActor
    private func startImport() async {
        guard let card = selectedCard, !destinationPath.isEmpty else { return }
        let destination = URL(filePath: destinationPath)
        isImporting = true

        importTask = Task {
            await ImportService.shared.importFiles(from: card, to: destination, schema: selectedSchema) { prog in
                Task { @MainActor in
                    self.progress = prog
                    if prog.done { self.isImporting = false }
                }
            }
        }

        await importTask?.value
    }
}
