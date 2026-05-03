import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    private var sessionsByYear: [(String, [PhotoSession])] {
        let grouped = Dictionary(grouping: appState.sessions) {
            String($0.dateString.prefix(4))
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: Bindable(appState).selectedSession) {
            if appState.sessions.isEmpty {
                emptyContent
            } else {
                ForEach(sessionsByYear, id: \.0) { (year, sessions) in
                    Section(year) {
                        ForEach(sessions) { session in
                            SessionRowView(session: session)
                                .tag(session)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.pickCameraRoot()
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .help(appState.cameraRoot.map { "Library: \($0.lastPathComponent)\nClick to change" } ?? "Choose library folder")
            }
        }
        .onChange(of: appState.selectedSession) { _, newSession in
            if let session = newSession {
                Task { await appState.selectSession(session) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                Button {
                    appState.showImport = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Import")
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Import from SD card")

                Divider().frame(height: 20)

                Button {
                    appState.showSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.callout)
                        .frame(width: 44)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .foregroundStyle(.secondary)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if appState.cameraRoot == nil {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text("No library selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Choose…") { appState.pickCameraRoot() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(.quaternary)
                Text("No sessions found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
}

// MARK: - SessionRowView

struct SessionRowView: View {
    let session: PhotoSession
    @Environment(AppState.self) private var appState

    @State private var thumbURL: URL? = nil
    @State private var enrichmentStatus: SessionEnrichmentStatus = .unknown

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            Group {
                if let url = thumbURL {
                    ThumbnailView(url: url, size: 120, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.fill.tertiary)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 14))
                                .foregroundStyle(.quaternary)
                        }
                }
            }
            .frame(width: 56, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(session.dateString)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.medium)

                if let label = session.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if session.editedCount > 0 || session.originalsCount > 0 {
                    editedBar
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 4)

            // Status + Counts
            VStack(alignment: .trailing, spacing: 4) {
                // Enrichment status (processing overrides static status)
                if isProcessing {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appAmber)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: enrichmentStatus.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                }

                // Photo counts
                HStack(spacing: 4) {
                    Text("\(session.editedCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.appAmber.opacity(0.85), in: Capsule())

                    if session.originalsCount > 0 {
                        Text("\(session.originalsCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .task(id: session.id) {
            async let thumb = PhotoScanner.shared.firstPhotoURL(
                in: session,
                picksFolderName: appState.picksFolderName
            )
            async let status = PhotoScanner.shared.checkEnrichmentStatus(
                for: session,
                picksFolderName: appState.picksFolderName
            )
            thumbURL = await thumb
            enrichmentStatus = await status
        }
    }

    private var isProcessing: Bool {
        appState.selectedSession?.id == session.id && !appState.enrichingIDs.isEmpty
    }

    private var statusColor: Color {
        switch enrichmentStatus {
        case .unknown:  .secondary.opacity(0.3)
        case .pending:  .secondary.opacity(0.5)
        case .partial:  Color.appAmber.opacity(0.7)
        case .enriched: Color.appAmber
        }
    }

    private var editedBar: some View {
        let total = max(session.editedCount, session.originalsCount)
        let fraction = total > 0 ? Double(session.editedCount) / Double(total) : 0

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.fill.tertiary)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 2)
                    .fill(fraction >= 1.0 ? Color.green : Color.appAmber)
                    .frame(width: geo.size.width * fraction, height: 3)
                    .animation(.easeInOut, value: fraction)
            }
        }
        .frame(height: 3)
    }
}
