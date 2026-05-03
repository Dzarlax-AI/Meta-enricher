import SwiftUI

// MARK: - PhotoCardView

struct PhotoCardView: View {
    @Environment(AppState.self) private var appState
    let photo: Photo

    @State private var isHovered = false

    private var hoverOverlayHeight: CGFloat {
        let hasTitle    = !(photo.meta.title    ?? "").isEmpty
        let hasLocation = !(photo.meta.location ?? "").isEmpty
        switch (hasTitle, hasLocation) {
        case (true,  true):  return 80
        case (true,  false): return 62
        case (false, true):  return 52
        case (false, false): return 44
        }
    }

    private var isSelected: Bool {
        appState.selectedPhotoIDs.contains(photo.id) || appState.selectedPhoto?.id == photo.id
    }
    private var isEnriching: Bool { appState.enrichingIDs.contains(photo.id) }

    var body: some View {
        ThumbnailView(url: photo.url, size: 1200)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // All overlays are inside .overlay so they never expand the card's height
            .overlay {
                ZStack {
                    // Bottom frosted bar + meta on hover
                    if isHovered {
                        VStack(alignment: .leading, spacing: 2) {
                            if let title = photo.meta.title, !title.isEmpty {
                                Text(title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                            if let location = photo.meta.location, !location.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 8))
                                    Text(location)
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                            Text(photo.url.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }

                    // Top-left: checkbox
                    if isHovered || !appState.selectedPhotoIDs.isEmpty {
                        checkboxOverlay
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.scale(scale: 0.5, anchor: .topLeading).combined(with: .opacity))
                    }

                    // Top-right: enrichment badge
                    enrichmentBadge
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)

                    // Bottom-left: star rating
                    if let rating = photo.meta.rating, rating > 0 {
                        ratingBadge(rating: rating)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(6)
                    }

                    // Selected ring
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.appAmber, lineWidth: 2.5)
                    }

                    // Enriching scan animation
                    if isEnriching {
                        EnrichmentScanOverlay()
                    }
                }
            }
            .shadow(
                color: isSelected
                    ? Color.appAmber.opacity(0.4)
                    : .black.opacity(isHovered ? 0.28 : 0.14),
                radius: isSelected ? 10 : (isHovered ? 8 : 3),
                y: isHovered ? 4 : 1
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) {
                appState.selectedPhoto = photo
                appState.fullscreenPhoto = photo
                appState.showFullscreen = true
            }
            .onTapGesture(count: 1) {
                appState.selectedPhoto = photo
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Subviews

    private var checkboxOverlay: some View {
        Button { toggleSelection() } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.appAmber : .white)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .buttonStyle(.plain)
        .padding(6)
    }

    @ViewBuilder
    private var enrichmentBadge: some View {
        if photo.isEnriched {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.appAmber, in: Capsule())
        } else if photo.hasPartialMeta {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.appAmber.opacity(0.4), in: Capsule())
        }
    }

    private func ratingBadge(rating: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: 7))
                    .foregroundStyle(star <= rating ? .yellow : .white.opacity(0.4))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func toggleSelection() {
        if appState.selectedPhotoIDs.contains(photo.id) {
            appState.selectedPhotoIDs.remove(photo.id)
        } else {
            appState.selectedPhotoIDs.insert(photo.id)
        }
    }
}

// MARK: - ThumbnailView

struct ThumbnailView: View {
    let url: URL
    let size: CGFloat
    var contentMode: ContentMode = .fit

    @State private var image: NSImage? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                Rectangle()
                    .fill(.fill.tertiary)
                    .frame(minHeight: 120)
                    .overlay { ProgressView().scaleEffect(0.6) }
            } else {
                Rectangle()
                    .fill(.fill.secondary)
                    .frame(minHeight: 120)
                    .overlay { Image(systemName: "photo").foregroundStyle(.quaternary) }
            }
        }
        .task(id: url) {
            isLoading = true
            image = await ThumbnailService.shared.thumbnail(for: url, size: size)
            isLoading = false
        }
    }
}
