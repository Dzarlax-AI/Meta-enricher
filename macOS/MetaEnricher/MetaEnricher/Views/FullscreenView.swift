import SwiftUI
import AppKit

struct FullscreenView: View {
    @Environment(AppState.self) private var appState
    let photo: Photo

    @State private var previewImage: NSImage? = nil
    @State private var thumbImage:   NSImage? = nil
    @State private var fullImage:    NSImage? = nil
    @State private var isLoadingFull = false
    @FocusState private var isFocused: Bool

    // Zoom & pan
    @State private var zoomScale:     CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset:     CGSize  = .zero
    @State private var lastPanOffset: CGSize  = .zero
    @State private var scrollMonitor: Any?    = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            let displayImage = fullImage ?? previewImage ?? thumbImage
            if let img = displayImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale)
                    .offset(panOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, zoomScale <= 1.0 ? 56 : 0)
                    .gesture(magnificationGesture)
                    .gesture(panGesture)
                    .onTapGesture(count: 2) { resetZoom() }
                    .onTapGesture(count: 1) { if zoomScale <= 1.0 { dismiss() } }
            } else {
                ProgressView().tint(.white)
            }

            // Top bar
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Button { rotate(clockwise: false) } label: {
                            Image(systemName: "rotate.left")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Rotate counter-clockwise")

                        Button { rotate(clockwise: true) } label: {
                            Image(systemName: "rotate.right")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Rotate clockwise")

                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                        .help("Close (Esc)")
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }

                Spacer()

                if zoomScale <= 1.0 {
                    bottomBar.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Zoom level + HD loading hint
            if zoomScale > 1.01 {
                VStack {
                    HStack(spacing: 6) {
                        Text(String(format: "%.0f%%", zoomScale * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())

                        if isLoadingFull {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.6).tint(.white)
                                Text("HD")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.opacity)
                        } else if fullImage != nil {
                            Text("HD")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.opacity)
                        }

                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: zoomScale <= 1.0)
        .animation(.easeInOut(duration: 0.15), value: zoomScale > 1.01)
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow)  { navigatePrev(); return .handled }
        .onKeyPress(.rightArrow) { navigateNext(); return .handled }
        .onKeyPress(.escape)     { dismiss();      return .handled }
        .onKeyPress(.init("="))  { zoomStep(1.3);  return .handled }
        .onKeyPress(.init("-"))  { zoomStep(1/1.3); return .handled }
        .onKeyPress(.init("0"))  { resetZoom();    return .handled }
        .onAppear {
            isFocused = true
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let dy = event.scrollingDeltaY
                guard dy != 0 else { return event }
                let factor = 1.0 + dy * 0.05
                DispatchQueue.main.async {
                    withAnimation(.interactiveSpring(duration: 0.1)) {
                        zoomScale = max(1.0, min(10.0, zoomScale * factor))
                        lastZoomScale = zoomScale
                        if zoomScale <= 1.0 { resetPan() }
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        }
        .task(id: photo.id) { await loadImages() }
        .onChange(of: photo.id) { _, _ in
            fullImage = nil
            isLoadingFull = false
            resetZoom()
        }
        .onChange(of: zoomScale) { _, newScale in
            if newScale > 1.5 && fullImage == nil && !isLoadingFull {
                Task { await loadFullImage() }
            }
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = max(1.0, min(10.0, lastZoomScale * value))
            }
            .onEnded { value in
                zoomScale = max(1.0, min(10.0, lastZoomScale * value))
                lastZoomScale = zoomScale
                if zoomScale <= 1.0 { resetPan() }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1.0 else { return }
                panOffset = CGSize(
                    width:  lastPanOffset.width  + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = panOffset
            }
    }

    // MARK: - Zoom Helpers

    private func zoomStep(_ factor: CGFloat) {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(1.0, min(10.0, zoomScale * factor))
            lastZoomScale = zoomScale
            if zoomScale <= 1.0 { resetPan() }
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            zoomScale = 1.0
            lastZoomScale = 1.0
            resetPan()
        }
    }

    private func resetPan() {
        panOffset = .zero
        lastPanOffset = .zero
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button { navigatePrev() } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(prevPhoto != nil ? .white : .gray)
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(prevPhoto == nil)

            VStack(spacing: 2) {
                Text(photo.url.lastPathComponent)
                    .foregroundStyle(.white)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    if let make = photo.meta.make, let model = photo.meta.model { Text("\(make) \(model)") }
                    if let fl = photo.meta.focalLength   { Text(fl) }
                    if let ap = photo.meta.aperture      { Text(ap) }
                    if let ss = photo.meta.shutterSpeed  { Text(ss) }
                    if let iso = photo.meta.iso          { Text("ISO \(iso)") }
                    if let date = photo.meta.dateTimeOriginal { Text(date) }
                }
                .foregroundStyle(.white.opacity(0.7))
                .font(.caption)
            }
            .frame(maxWidth: .infinity)

            Button { navigateNext() } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(nextPhoto != nil ? .white : .gray)
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(nextPhoto == nil)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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

    private func navigatePrev() { if let p = prevPhoto { appState.fullscreenPhoto = p } }
    private func navigateNext() { if let p = nextPhoto { appState.fullscreenPhoto = p } }

    private func dismiss() {
        appState.showFullscreen  = false
        appState.fullscreenPhoto = nil
    }

    // MARK: - Image Loading

    private func loadImages() async {
        thumbImage   = await ThumbnailService.shared.thumbnail(for: photo.url, size: 400)
        previewImage = await ThumbnailService.shared.thumbnail(for: photo.url, size: 1600)
    }

    private func loadFullImage() async {
        guard !isLoadingFull, fullImage == nil else { return }
        isLoadingFull = true
        let url = photo.url
        let image = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        fullImage = image
        isLoadingFull = false
    }

    // MARK: - Rotation

    private func rotate(clockwise: Bool) {
        Task {
            do {
                try await ExifService.shared.rotateOrientation(url: photo.url, clockwise: clockwise)
            } catch {
                print("[FullscreenView] Rotation failed: \(error.localizedDescription)")
            }
            await ThumbnailService.shared.invalidate(url: photo.url)
            previewImage = nil
            thumbImage   = nil
            fullImage    = nil
            await loadImages()
        }
    }
}

