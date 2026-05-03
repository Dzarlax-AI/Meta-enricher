import SwiftUI
import AppKit

struct GalleryView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isFocused: Bool

    @State private var columnCount = 3

    // columnCount → slider value: more columns = smaller photos (higher slider = larger = fewer columns)
    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(7 - columnCount) },       // 2 cols → 5, 6 cols → 1
            set: { columnCount = 7 - Int($0.rounded()) }
        )
    }

    var body: some View {
        Group {
            if appState.isLoadingPhotos {
                loadingState
            } else if appState.photos.isEmpty {
                emptyState
            } else {
                galleryGrid
            }
        }
        .navigationTitle(appState.selectedSession?.displayName ?? "")
        .navigationSubtitle("\(appState.photos.count) photos")
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow)  { navigatePrev(); return .handled }
        .onKeyPress(.rightArrow) { navigateNext(); return .handled }
        .onKeyPress(.escape)     { appState.selectedPhotoIDs = []; return .handled }
        .background {
            Group {
                Button("") { withAnimation(.easeInOut(duration: 0.2)) { columnCount = max(2, columnCount - 1) } }
                    .keyboardShortcut("+", modifiers: .command)
                Button("") { withAnimation(.easeInOut(duration: 0.2)) { columnCount = max(2, columnCount - 1) } }
                    .keyboardShortcut("=", modifiers: .command)
                Button("") { withAnimation(.easeInOut(duration: 0.2)) { columnCount = min(6, columnCount + 1) } }
                    .keyboardShortcut("-", modifiers: .command)
                Button("") { withAnimation(.easeInOut(duration: 0.2)) { columnCount = 3 } }
                    .keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - Gallery Grid

    private var galleryGrid: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<columnCount, id: \.self) { col in
                    LazyVStack(spacing: 16) {
                        ForEach(photosForColumn(col)) { photo in
                            PhotoCardView(photo: photo)
                                .environment(appState)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 64) // space for zoom control
        }
        .background(Color(white: 0.15))
        .safeAreaInset(edge: .top, spacing: 0) {
            sessionNotesBar
        }
        .overlay(alignment: .bottomTrailing) {
            zoomControl
        }
        .scrollContentBackground(.hidden)
    }

    private func photosForColumn(_ col: Int) -> [Photo] {
        appState.photos.enumerated()
            .filter { $0.offset % columnCount == col }
            .map(\.element)
    }

    // MARK: - Zoom Control

    private var zoomControl: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { columnCount = min(6, columnCount + 1) }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .disabled(columnCount >= 6)

            Slider(value: sliderValue, in: 1...5, step: 1)
                .frame(width: 80)
                .onChange(of: sliderValue.wrappedValue) { _, _ in
                    // animation handled by binding
                }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { columnCount = max(2, columnCount - 1) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .disabled(columnCount <= 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Session Notes Bar

    private var sessionNotesBar: some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 6) {
            Label("AI Context", systemImage: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.appAmber)

            TextField("Describe the session: location, event, shooting style — helps AI write better metadata", text: $appState.sessionNotes)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.22))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.appAmber.opacity(0.6))
                .frame(height: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Loading photos…")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.15))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52))
                .foregroundStyle(.quaternary)
            Text("No photos in this session")
                .font(.title3)
            Text("Switch to Originals or check the folder structure.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.15))
    }

    // MARK: - Keyboard Navigation

    private func navigatePrev() {
        guard let current = appState.selectedPhoto,
              let idx = appState.photos.firstIndex(where: { $0.id == current.id }),
              idx > 0 else { return }
        appState.selectedPhoto = appState.photos[idx - 1]
    }

    private func navigateNext() {
        guard let current = appState.selectedPhoto,
              let idx = appState.photos.firstIndex(where: { $0.id == current.id }),
              idx < appState.photos.count - 1 else { return }
        appState.selectedPhoto = appState.photos[idx + 1]
    }
}
