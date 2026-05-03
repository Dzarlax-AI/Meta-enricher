import Foundation

actor PhotoScanner {
    static let shared = PhotoScanner()

    // Finds all sessions (folders containing "Edited export" subfolder)
    func findSessions(in root: URL) async -> [PhotoSession] {
        var sessions: [PhotoSession] = []
        let fm = FileManager.default

        guard let yearDirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }

        for yearDir in yearDirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard (try? yearDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            guard let dateDirs = try? fm.contentsOfDirectory(
                at: yearDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
            ) else { continue }

            for dateDir in dateDirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                guard (try? dateDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

                let editedExport = dateDir.appending(path: "Edited export")
                let jpegFolder   = dateDir.appending(path: "JPEG")

                let hasEdited = fm.fileExists(atPath: editedExport.path)
                let hasJpeg   = fm.fileExists(atPath: jpegFolder.path)
                guard hasEdited || hasJpeg else { continue }

                let folderName = dateDir.lastPathComponent
                let (dateStr, label) = parseFolderName(folderName)

                let editedCount    = hasEdited ? photoCount(in: editedExport) : 0
                let originalsCount = hasJpeg   ? photoCount(in: jpegFolder)   : 0
                let session = PhotoSession(
                    id: dateDir.path,
                    folderURL: dateDir,
                    dateString: dateStr,
                    label: label,
                    editedCount: editedCount,
                    originalsCount: originalsCount,
                    enrichedCount: 0
                )
                sessions.append(session)
            }
        }
        return sessions
    }

    func loadPhotos(in session: PhotoSession, mode: ViewMode) async -> [Photo] {
        let subdir: URL
        switch mode {
        case .edited:    subdir = session.folderURL.appending(path: "Edited export")
        case .originals: subdir = session.folderURL.appending(path: "JPEG")
        }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: subdir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        let imageExtensions = Set(["jpg", "jpeg", "png", "tif", "tiff"])
        let imageFiles = files
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var photos: [Photo] = []
        for url in imageFiles {
            let meta = await ExifService.shared.readMeta(from: url)
            photos.append(Photo(id: url.path, url: url, meta: meta))
        }
        return photos
    }

    // MARK: - Helpers

    private func parseFolderName(_ name: String) -> (date: String, label: String?) {
        // Format: "2026-03-07" or "2026-03-07 Some Label"
        let parts = name.split(separator: " ", maxSplits: 1)
        let date = String(parts[0])
        let label = parts.count > 1 ? String(parts[1]) : nil
        return (date, label)
    }

    private func photoCount(in dir: URL) -> Int {
        let exts = Set(["jpg", "jpeg", "png", "tif", "tiff"])
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return files.filter { exts.contains($0.pathExtension.lowercased()) }.count
    }

    func checkEnrichmentStatus(for session: PhotoSession, picksFolderName: String = "Edited export") async -> SessionEnrichmentStatus {
        let fm = FileManager.default
        let exts = Set(["jpg", "jpeg", "png", "tif", "tiff"])

        let dir = session.folderURL.appending(path: picksFolderName)
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return .pending }

        let images = files.filter { exts.contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else { return .pending }

        // Sample up to 3 photos for a quick estimate
        let sample = images.prefix(3)
        var enrichedCount = 0
        var partialCount = 0

        for url in sample {
            let meta = await ExifService.shared.readMeta(from: url)
            if meta.title != nil && meta.description != nil {
                enrichedCount += 1
            } else if meta.title != nil || !meta.keywords.isEmpty {
                partialCount += 1
            }
        }

        if enrichedCount == sample.count { return .enriched }
        if enrichedCount > 0 || partialCount > 0 { return .partial }
        return .pending
    }

    func firstPhotoURL(in session: PhotoSession, picksFolderName: String = "Edited export") -> URL? {
        let fm = FileManager.default
        let exts = Set(["jpg", "jpeg", "png", "tif", "tiff"])
        for subdir in [picksFolderName, "Edited export", "JPEG"] {
            let dir = session.folderURL.appending(path: subdir)
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            if let first = files
                .filter({ exts.contains($0.pathExtension.lowercased()) })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first { return first }
        }
        return nil
    }
}
