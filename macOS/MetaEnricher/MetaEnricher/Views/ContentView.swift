import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var inspectorPresented = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var enrichConflict: EnrichConflict? = nil

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            if appState.selectedSession != nil {
                GalleryView()
                    .inspector(isPresented: $inspectorPresented) {
                        if appState.selectedPhotoIDs.count > 1 {
                            BulkInspectorView { fields in
                                await enrichSelected(fields: fields)
                            }
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                        } else if let photo = appState.selectedPhoto {
                            DetailView(photo: photo)
                                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
                        } else {
                            Text("Select a photo")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .toolbar {
                        toolbarContent
                    }
                    .onChange(of: appState.selectedPhoto) { _, newValue in
                        if newValue != nil {
                            withAnimation { inspectorPresented = true }
                        }
                    }
                    .onChange(of: appState.selectedPhotoIDs) { _, newValue in
                        if newValue.count > 1 {
                            withAnimation { inspectorPresented = true }
                        }
                    }
                    .confirmationDialog(
                        "Some photos already have metadata",
                        isPresented: Binding(
                            get: { enrichConflict != nil },
                            set: { if !$0 { enrichConflict = nil } }
                        ),
                        titleVisibility: .visible,
                        presenting: enrichConflict
                    ) { conflict in
                        Button("Overwrite All") {
                            Task { await performEnrich(conflict.photos, fields: conflict.fields, overwrite: true) }
                        }
                        Button("Fill Empty Only") {
                            Task { await performEnrich(conflict.photos, fields: conflict.fields, overwrite: false) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: { conflict in
                        let fieldNames = conflict.fields
                            .sorted { $0.displayName < $1.displayName }
                            .map(\.displayName)
                            .joined(separator: ", ")
                        let n = conflict.conflictCount
                        let total = conflict.photos.count
                        if n == total {
                            Text("\(n == 1 ? "This photo" : "All \(n) photos") already \(n == 1 ? "has" : "have") \(fieldNames) filled in.")
                        } else {
                            Text("\(n) of \(total) photos already have \(fieldNames) filled in.")
                        }
                    }
            } else {
                emptyState
            }
        }
        .sheet(isPresented: Bindable(appState).showImport) {
            ImportView()
                .environment(appState)
        }
        .sheet(isPresented: Bindable(appState).showSettings) {
            SettingsView()
                .environment(appState)
        }
        .overlay {
            if appState.showFullscreen, let photo = appState.fullscreenPhoto {
                FullscreenView(photo: photo)
                    .environment(appState)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var appState = appState

        ToolbarItem(placement: .navigation) {
            Picker("View", selection: Bindable(appState).viewMode) {
                Text("Edited").tag(ViewMode.edited)
                Text("Originals").tag(ViewMode.originals)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: appState.viewMode) { _, _ in
                Task { await appState.reloadCurrentSession() }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await enrichSelected() }
            } label: {
                Label("Enrich Selected", systemImage: "sparkles")
            }
            .disabled(appState.selectedPhotoIDs.isEmpty && appState.selectedPhoto == nil)
            .help("Enrich selected photos with AI")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                let ids = Set(appState.photos.map(\.id))
                appState.selectedPhotoIDs = ids
            } label: {
                Label("Select All", systemImage: "checkmark.circle")
            }
            .help("Select all photos")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { inspectorPresented.toggle() }
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle inspector panel")
        }

    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.quaternary)

            if appState.cameraRoot == nil {
                VStack(spacing: 8) {
                    Text("No Photo Library Selected")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Set your camera library root folder to get started.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Choose Library Folder") {
                        appState.pickCameraRoot()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Select a Session")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Choose a shooting session from the sidebar.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Enrichment

    private func enrichSelected() async {
        await enrichSelected(fields: Set(EnrichField.allCases))
    }

    private func enrichSelected(fields: Set<EnrichField>) async {
        let photos = resolvePhotosToEnrich()
        guard !photos.isEmpty else { return }

        let conflictCount = photos.filter { hasMetadataConflict($0, fields: fields) }.count
        if conflictCount > 0 {
            enrichConflict = EnrichConflict(fields: fields, conflictCount: conflictCount, photos: photos)
            return
        }

        await performEnrich(photos, fields: fields, overwrite: true)
    }

    private func resolvePhotosToEnrich() -> [Photo] {
        if !appState.selectedPhotoIDs.isEmpty {
            return appState.photos.filter { appState.selectedPhotoIDs.contains($0.id) }
        } else if let photo = appState.selectedPhoto {
            return [photo]
        }
        return []
    }

    private func hasMetadataConflict(_ photo: Photo, fields: Set<EnrichField>) -> Bool {
        if fields.contains(.title)       && !(photo.meta.title       ?? "").isEmpty { return true }
        if fields.contains(.description) && !(photo.meta.description ?? "").isEmpty { return true }
        if fields.contains(.keywords)    && !photo.meta.keywords.isEmpty            { return true }
        if fields.contains(.location)    && !(photo.meta.location    ?? "").isEmpty { return true }
        return false
    }

    private func performEnrich(_ photos: [Photo], fields: Set<EnrichField>, overwrite: Bool) async {
        enrichConflict = nil
        let baseURL = appState.ollamaURL
        let model   = appState.ollamaModel
        let notes   = appState.sessionNotes

        for photo in photos {
            guard !appState.enrichingIDs.contains(photo.id) else { continue }
            appState.enrichingIDs.insert(photo.id)

            do {
                var aiMeta = try await OllamaService.shared.enrichPhoto(
                    imageURL: photo.url,
                    baseURL: baseURL,
                    model: model,
                    sessionNotes: notes,
                    existingMeta: photo.meta,
                    fields: fields
                )

                if fields.contains(.location),
                   aiMeta.location == nil,
                   let lat = photo.meta.gpsLat,
                   let lon = photo.meta.gpsLon {
                    let geo = await GeocodingService.shared.reverseGeocode(lat: lat, lon: lon)
                    if let city = geo.city, let country = geo.country {
                        aiMeta.location = "\(city), \(country)"
                        aiMeta.locationSource = "gps"
                    }
                }

                var merged = photo.meta
                if fields.contains(.title) {
                    merged.title = overwrite
                        ? (aiMeta.title ?? merged.title)
                        : (merged.title ?? aiMeta.title)
                }
                if fields.contains(.description) {
                    merged.description = overwrite
                        ? (aiMeta.description ?? merged.description)
                        : (merged.description ?? aiMeta.description)
                }
                if fields.contains(.keywords) && !aiMeta.keywords.isEmpty {
                    if overwrite || merged.keywords.isEmpty {
                        merged.keywords = aiMeta.keywords
                    }
                }
                if fields.contains(.location) {
                    if overwrite || merged.location == nil {
                        merged.location       = aiMeta.location       ?? merged.location
                        merged.locationSource = aiMeta.locationSource ?? merged.locationSource
                    }
                }

                let locationParts = merged.location?.components(separatedBy: ", ")
                let writeCmd = MetaWrite(
                    title:       merged.title,
                    description: merged.description,
                    keywords:    Array(Set(merged.keywords)),
                    city:        locationParts?.first,
                    country:     locationParts?.count == 2 ? locationParts?.last : nil,
                    rating:      merged.rating,
                    creator:     merged.creator,
                    copyright:   merged.copyright,
                    gpsLat:      merged.gpsLat,
                    gpsLon:      merged.gpsLon
                )
                try await ExifService.shared.writeMeta(to: photo.url, meta: writeCmd)

                let updated = Photo(id: photo.id, url: photo.url, meta: merged)
                appState.updatePhoto(updated)
            } catch {
                print("[Enrich] ⚠️ \(photo.url.lastPathComponent): \(error.localizedDescription)")
            }

            appState.enrichingIDs.remove(photo.id)
        }
    }
}

// MARK: - EnrichConflict

private struct EnrichConflict: Identifiable {
    let id = UUID()
    let fields: Set<EnrichField>
    let conflictCount: Int
    let photos: [Photo]
}
