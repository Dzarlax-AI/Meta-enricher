import SwiftUI
import Foundation

enum ViewMode: String, CaseIterable {
    case edited = "Edited"
    case originals = "Originals"
}

enum LibrarySchema: String {
    case metaEnricher = "metaEnricher"
    case custom       = "custom"
}

@Observable
final class AppState {
    // Onboarding
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    var librarySchema: LibrarySchema = LibrarySchema(rawValue: UserDefaults.standard.string(forKey: "librarySchema") ?? "") ?? .metaEnricher
    var picksFolder: URL? = {
        guard let p = UserDefaults.standard.string(forKey: "picksFolder") else { return nil }
        return URL(filePath: p)
    }()
    var picksFolderName: String = UserDefaults.standard.string(forKey: "picksFolderName") ?? "Edited export"

    // Settings
    var cameraRoot: URL? {
        didSet {
            if let url = cameraRoot {
                Self.saveBookmark(for: url, key: "cameraRootBookmark")
            }
            Task { await loadSessions() }
        }
    }
    var ollamaURL: String = UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434"
    var ollamaModel: String = UserDefaults.standard.string(forKey: "ollamaModel") ?? "qwen2.5vl"
    var defaultCreator: String = UserDefaults.standard.string(forKey: "defaultCreator") ?? ""
    var defaultCopyright: String = UserDefaults.standard.string(forKey: "defaultCopyright") ?? ""

    // Sessions
    var sessions: [PhotoSession] = []
    var selectedSession: PhotoSession?

    // Photos
    var photos: [Photo] = []
    var selectedPhoto: Photo?
    var selectedPhotoIDs: Set<String> = []
    var viewMode: ViewMode = .edited
    var isLoadingPhotos = false

    // UI state
    var showSettings = false
    var showImport = false
    var showFullscreen = false
    var fullscreenPhoto: Photo?

    // Enrichment
    var enrichingIDs: Set<String> = []

    // Session notes (context for AI enrichment)
    var sessionNotes: String = "" {
        didSet {
            guard let id = selectedSession?.id else { return }
            UserDefaults.standard.set(sessionNotes, forKey: "sessionNotes_\(id)")
        }
    }

    init() {
        cameraRoot = Self.restoreBookmark(key: "cameraRootBookmark")
        Task { await loadSessions() }
    }

    // MARK: - Security-Scoped Bookmarks

    static func saveBookmark(for url: URL, key: String) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: key)
        } catch {
            NSLog("[AppState] Failed to save bookmark for %@: %@", key, error.localizedDescription)
        }
    }

    static func restoreBookmark(key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard url.startAccessingSecurityScopedResource() else {
            NSLog("[AppState] Failed to start accessing security-scoped resource for %@", key)
            return nil
        }
        if isStale {
            NSLog("[AppState] Bookmark for %@ was stale, refreshing", key)
            saveBookmark(for: url, key: key)
        }
        return url
    }

    @MainActor
    func loadSessions() async {
        guard let root = cameraRoot else { sessions = []; return }
        sessions = await PhotoScanner.shared.findSessions(in: root)
    }

    @MainActor
    func selectSession(_ session: PhotoSession) async {
        selectedSession = session
        selectedPhotoIDs = []
        selectedPhoto = nil
        sessionNotes = UserDefaults.standard.string(forKey: "sessionNotes_\(session.id)") ?? ""
        isLoadingPhotos = true
        photos = await PhotoScanner.shared.loadPhotos(in: session, mode: viewMode)
        isLoadingPhotos = false
    }

    @MainActor
    func reloadCurrentSession() async {
        guard let session = selectedSession else { return }
        await selectSession(session)
    }

    func pickCameraRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your photo library root folder"
        panel.prompt = "Select"
        if panel.runModal() == .OK {
            cameraRoot = panel.url
        }
    }

    func updatePhoto(_ updated: Photo) {
        if let idx = photos.firstIndex(where: { $0.id == updated.id }) {
            photos[idx] = updated
        }
        if selectedPhoto?.id == updated.id {
            selectedPhoto = updated
        }
    }
}
