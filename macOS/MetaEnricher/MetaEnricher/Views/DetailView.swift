import SwiftUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    let photo: Photo

    @State private var title       = ""
    @State private var description = ""
    @State private var keywords: [String] = []
    @State private var location    = ""
    @State private var rating      = 0
    @State private var creator     = ""
    @State private var copyright   = ""
    @State private var newKeyword  = ""

    @State private var isSaving    = false
    @State private var isEnriching = false
    @State private var saveError: String?
    @State private var showError   = false

    @State private var enrichFields: Set<EnrichField> = Set(EnrichField.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                previewSection
                metadataSection
                cameraSection
                actionButtons
            }
        }
        .onAppear { populateFields(from: photo) }
        .onChange(of: photo.id) { _, _ in populateFields(from: photo) }
        .alert("Save Error", isPresented: $showError, presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { err in
            Text(err)
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        ZStack(alignment: .bottom) {
            ThumbnailView(url: photo.url, size: 1200, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .onTapGesture { openFullscreen() }

            // Bottom frosted nav bar — no gradient
            HStack(spacing: 8) {
                Button { navigatePrev() } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(prevPhoto == nil)
                .opacity(prevPhoto == nil ? 0.3 : 1)

                Text(photo.url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)

                Button { navigateNext() } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(nextPhoto == nil)
                .opacity(nextPhoto == nil ? 0.3 : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Fullscreen button
            Button { openFullscreen() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(8)
        }
        .frame(height: 280)
        .clipped()
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Metadata", icon: "tag")

            VStack(alignment: .leading, spacing: 12) {
                MetaField(label: "Rating") {
                    ratingPicker
                }

                MetaField(label: "Title", enrichSelected: enrichBinding(.title)) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .inspectorField()
                }

                MetaField(label: "Description", enrichSelected: enrichBinding(.description)) {
                    TextEditor(text: $description)
                        .font(.callout)
                        .frame(minHeight: 56, maxHeight: 80)
                        .scrollContentBackground(.hidden)
                        .inspectorField()
                }

                MetaField(label: "Keywords", enrichSelected: enrichBinding(.keywords)) {
                    keywordsEditor
                }

                MetaField(label: "Location", enrichSelected: enrichBinding(.location)) {
                    TextField("City, Country", text: $location)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .inspectorField()
                }

                MetaField(label: "Creator") {
                    TextField("Photographer name", text: $creator)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .inspectorField()
                }

                MetaField(label: "Copyright") {
                    TextField("© 2026 …", text: $copyright)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .inspectorField()
                }
            }
            .padding(12)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    private var ratingPicker: some View {
        HStack(spacing: 4) {
            Button { rating = 0 } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(rating == 0 ? Color.appAmber : .secondary)
                    .frame(width: 18, height: 18)
                    .background(rating == 0 ? Color.appAmber.opacity(0.15) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)

            ForEach(1...5, id: \.self) { star in
                Button { rating = star } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(star <= rating ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var keywordsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !keywords.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(Array(keywords.enumerated()), id: \.offset) { _, kw in
                        HStack(spacing: 3) {
                            Text(kw)
                                .font(.caption)
                            Button {
                                keywords.removeAll { $0 == kw }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appAmber.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.appAmber)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add keyword…", text: $newKeyword)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .inspectorField()
                    .onSubmit { addKeyword() }

                Button("Add") { addKeyword() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Camera Section

    private var cameraSection: some View {
        let rows = cameraRows
        guard !rows.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                InspectorSectionHeader(title: "Camera", icon: "camera")

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        VStack(spacing: 0) {
                            HStack {
                                Text(row.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(row.value)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)

                            if idx < rows.count - 1 {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                }
                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        )
    }

    private var cameraRows: [(label: String, value: String)] {
        let exif = photo.meta
        var rows: [(String, String)] = []
        if let make = exif.make, let model = exif.model { rows.append(("Camera", "\(make) \(model)")) }
        if let fl = exif.focalLength                    { rows.append(("Focal",   fl)) }
        if let ap = exif.aperture                       { rows.append(("Aperture", ap)) }
        if let ss = exif.shutterSpeed                   { rows.append(("Shutter",  ss)) }
        if let iso = exif.iso                           { rows.append(("ISO",     "ISO \(iso)")) }
        if let date = exif.dateTimeOriginal             { rows.append(("Date",    date)) }
        if let lat = exif.gpsLat, let lon = exif.gpsLon {
            rows.append(("GPS", String(format: "%.5f, %.5f", lat, lon)))
        }
        return rows
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView().scaleEffect(0.8).frame(width: 60)
                } else {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)

            Button {
                Task { await enrichWithAI() }
            } label: {
                if isEnriching {
                    ProgressView().scaleEffect(0.8).frame(width: 70)
                } else if enrichFields.count == EnrichField.allCases.count {
                    Label("Enrich All", systemImage: "sparkles")
                } else {
                    Label("Enrich (\(enrichFields.count))", systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isEnriching || enrichFields.isEmpty)

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Navigation

    private var photoIndex: Int? { appState.photos.firstIndex(where: { $0.id == photo.id }) }
    private var prevPhoto: Photo? {
        guard let idx = photoIndex, idx > 0 else { return nil }
        return appState.photos[idx - 1]
    }
    private var nextPhoto: Photo? {
        guard let idx = photoIndex, idx < appState.photos.count - 1 else { return nil }
        return appState.photos[idx + 1]
    }
    private func navigatePrev() { if let p = prevPhoto { appState.selectedPhoto = p } }
    private func navigateNext() { if let p = nextPhoto { appState.selectedPhoto = p } }

    // MARK: - Actions

    private func populateFields(from p: Photo) {
        title       = p.meta.title       ?? ""
        description = p.meta.description ?? ""
        keywords    = p.meta.keywords
        location    = p.meta.location    ?? ""
        rating      = p.meta.rating      ?? 0
        creator     = p.meta.creator     ?? appState.defaultCreator
        copyright   = p.meta.copyright   ?? appState.defaultCopyright
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !keywords.contains(kw) else { newKeyword = ""; return }
        keywords.append(kw)
        newKeyword = ""
    }

    private func openFullscreen() {
        appState.fullscreenPhoto = photo
        appState.showFullscreen  = true
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let locationParts = location.components(separatedBy: ", ")
        let write = MetaWrite(
            title:       title.isEmpty       ? nil : title,
            description: description.isEmpty  ? nil : description,
            keywords:    keywords.isEmpty     ? nil : Array(Set(keywords)),
            city:        locationParts.count >= 1 && !locationParts[0].isEmpty ? locationParts[0] : nil,
            country:     locationParts.count == 2 ? locationParts[1] : nil,
            rating:      rating > 0 ? rating : nil,
            creator:     creator.isEmpty   ? nil : creator,
            copyright:   copyright.isEmpty ? nil : copyright
        )

        do {
            try await ExifService.shared.writeMeta(to: photo.url, meta: write)
            await ThumbnailService.shared.invalidate(url: photo.url)

            var updated = photo
            updated.meta.title       = write.title
            updated.meta.description = write.description
            updated.meta.keywords    = write.keywords ?? []
            updated.meta.location    = location.isEmpty ? nil : location
            updated.meta.rating      = write.rating
            updated.meta.creator     = write.creator
            updated.meta.copyright   = write.copyright
            appState.updatePhoto(updated)

        } catch {
            saveError = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func enrichWithAI() async {
        isEnriching = true
        defer { isEnriching = false }

        do {
            // Pass current form state as context for fields we're NOT regenerating
            var currentMeta = photo.meta
            currentMeta.title       = title.isEmpty       ? nil : title
            currentMeta.description = description.isEmpty ? nil : description
            currentMeta.keywords    = keywords
            currentMeta.location    = location.isEmpty    ? nil : location

            var aiMeta = try await OllamaService.shared.enrichPhoto(
                imageURL: photo.url,
                baseURL: appState.ollamaURL,
                model: appState.ollamaModel,
                sessionNotes: appState.sessionNotes,
                existingMeta: currentMeta,
                fields: enrichFields
            )

            if enrichFields.contains(.location),
               aiMeta.location == nil,
               let lat = photo.meta.gpsLat, let lon = photo.meta.gpsLon {
                let geo = await GeocodingService.shared.reverseGeocode(lat: lat, lon: lon)
                if let city = geo.city, let country = geo.country {
                    aiMeta.location = "\(city), \(country)"
                }
            }

            if enrichFields.contains(.title)       { title       = aiMeta.title       ?? title }
            if enrichFields.contains(.description) { description = aiMeta.description ?? description }
            if enrichFields.contains(.keywords) && !aiMeta.keywords.isEmpty { keywords = aiMeta.keywords }
            if enrichFields.contains(.location)    { location    = aiMeta.location    ?? location }
        } catch {
            saveError = error.localizedDescription
            showError = true
        }
    }

    private func enrichBinding(_ field: EnrichField) -> Binding<Bool> {
        Binding(
            get: { enrichFields.contains(field) },
            set: { if $0 { enrichFields.insert(field) } else { enrichFields.remove(field) } }
        )
    }

}

// MARK: - Inspector Section Header

private struct InspectorSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.appAmber)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Meta Field Row (Label on Top)

private struct MetaField<Content: View>: View {
    let label: String
    var enrichSelected: Binding<Bool>? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if let sel = enrichSelected {
                    Button { sel.wrappedValue.toggle() } label: {
                        Image(systemName: sel.wrappedValue ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(sel.wrappedValue ? Color.appAmber : Color.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(enrichSelected?.wrappedValue == false ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: enrichSelected?.wrappedValue)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
