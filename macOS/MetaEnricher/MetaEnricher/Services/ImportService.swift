import Foundation

// MARK: - ImportSchema

enum ImportSchema: String, CaseIterable, Identifiable, Sendable {
    case metaEnricher  = "MetaEnricher"
    case lightroom     = "Lightroom"
    case byYearMonth   = "By Year / Month"
    case byDate        = "By Date"
    case flat          = "Flat"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .metaEnricher: return "YYYY/YYYY-MM-DD/RAW|JPEG/ + Edited export/"
        case .lightroom:    return "YYYY/YYYY-MM-DD/filename"
        case .byYearMonth:  return "YYYY/MM/filename"
        case .byDate:       return "YYYY-MM-DD/filename"
        case .flat:         return "All files in destination root"
        }
    }
}

// MARK: - ImportProgress

struct ImportProgress: Sendable {
    var total: Int
    var copied: Int
    var currentFile: String
    var done: Bool
    var error: String?
}

// MARK: - ImportService

actor ImportService {
    static let shared = ImportService()

    private let rawExtensions:  Set<String> = ["arw", "nef", "cr2", "cr3", "dng", "raf", "orf", "rw2"]
    private let jpegExtensions: Set<String> = ["jpg", "jpeg"]

    // MARK: - Schema Detection

    /// Inspect the destination folder and guess the import schema from existing structure.
    nonisolated func detectSchema(in root: URL) -> ImportSchema {
        let fm = FileManager.default
        guard let yearDirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return .metaEnricher }

        // Look for YYYY directories
        let yearLike = yearDirs.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            && $0.lastPathComponent.range(of: #"^\d{4}$"#, options: .regularExpression) != nil
        }

        guard let firstYear = yearLike.first else {
            // No year dirs — check if there are date dirs (YYYY-MM-DD) or just files
            let dateLike = yearDirs.filter {
                $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
            }
            return dateLike.isEmpty ? .flat : .byDate
        }

        // Look inside the year dir
        guard let children = try? fm.contentsOfDirectory(
            at: firstYear, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return .metaEnricher }

        let dirs = children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        // YYYY/YYYY-MM-DD/... → Lightroom or MetaEnricher
        if let firstChild = dirs.first,
           firstChild.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
            // Check if there's RAW/JPEG/Edited export inside
            if let dateDirChildren = try? fm.contentsOfDirectory(
                at: firstChild, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) {
                let names = Set(dateDirChildren.map { $0.lastPathComponent })
                if names.contains("RAW") || names.contains("JPEG") || names.contains("Edited export") {
                    return .metaEnricher
                }
            }
            return .lightroom
        }

        // YYYY/MM/... → byYearMonth
        if let firstChild = dirs.first,
           firstChild.lastPathComponent.range(of: #"^\d{2}$"#, options: .regularExpression) != nil {
            return .byYearMonth
        }

        return .metaEnricher
    }

    /// Scan an existing library and find the most common picks subfolder name.
    nonisolated func detectPicksFolderName(in root: URL) -> String? {
        let common = ["Edited export", "Export", "Picks", "Finals", "Selected", "Published", "_picks"]
        let fm = FileManager.default
        var counts: [String: Int] = [:]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = url.lastPathComponent
            if common.contains(name) {
                counts[name, default: 0] += 1
            }
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - SD Card Detection

    /// Scan /Volumes for drives that contain a DCIM folder at the root level.
    func findSDCards() -> [URL] {
        let fm = FileManager.default
        guard let volumes = try? fm.contentsOfDirectory(
            at: URL(filePath: "/Volumes"),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return volumes.filter { vol in
            let dcim = vol.appending(path: "DCIM")
            return fm.fileExists(atPath: dcim.path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Import

    /// Import files from an SD card to the destination folder.
    func importFiles(
        from card: URL,
        to destination: URL,
        schema: ImportSchema = .metaEnricher,
        onProgress: @Sendable @escaping (ImportProgress) -> Void
    ) async {
        let dcim = card.appending(path: "DCIM")
        let fm = FileManager.default

        // Collect all eligible files recursively
        let allFiles = collectFiles(in: dcim)
        guard !allFiles.isEmpty else {
            onProgress(ImportProgress(total: 0, copied: 0, currentFile: "", done: true, error: "No media files found on card"))
            return
        }

        var progress = ImportProgress(total: allFiles.count, copied: 0, currentFile: "", done: false)
        onProgress(progress)

        for fileURL in allFiles {
            progress.currentFile = fileURL.lastPathComponent

            let date = extractDate(from: fileURL)
            let year = String(date.prefix(4))
            let month = String(date.dropFirst(5).prefix(2))
            let ext = fileURL.pathExtension.lowercased()
            let isRaw = rawExtensions.contains(ext)

            // Determine target directory based on schema
            let targetDir: URL
            switch schema {
            case .metaEnricher:
                targetDir = destination
                    .appending(path: year)
                    .appending(path: date)
                    .appending(path: isRaw ? "RAW" : "JPEG")
            case .lightroom:
                targetDir = destination
                    .appending(path: year)
                    .appending(path: date)
            case .byYearMonth:
                targetDir = destination
                    .appending(path: year)
                    .appending(path: month)
            case .byDate:
                targetDir = destination
                    .appending(path: date)
            case .flat:
                targetDir = destination
            }

            // For MetaEnricher schema also create Edited export folder
            if schema == .metaEnricher {
                let editedDir = destination
                    .appending(path: year)
                    .appending(path: date)
                    .appending(path: "Edited export")
                try? fm.createDirectory(at: editedDir, withIntermediateDirectories: true)
            }

            // Create target directory
            do {
                try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            } catch {
                progress.error = "Could not create directory: \(error.localizedDescription)"
                onProgress(progress)
                continue
            }

            let destFile = targetDir.appending(path: fileURL.lastPathComponent)

            // Skip if file already exists with same size
            if shouldSkip(source: fileURL, dest: destFile, fm: fm) {
                progress.copied += 1
                onProgress(progress)
                continue
            }

            do {
                try fm.copyItem(at: fileURL, to: destFile)
            } catch {
                // If dest already exists with different content, skip gracefully
                if (error as NSError).code != NSFileWriteFileExistsError {
                    progress.error = "Failed to copy \(fileURL.lastPathComponent): \(error.localizedDescription)"
                }
            }

            progress.copied += 1
            onProgress(progress)
        }

        progress.done = true
        progress.currentFile = ""
        onProgress(progress)
    }

    // MARK: - Helpers

    private func collectFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        let allExtensions = rawExtensions.union(jpegExtensions)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard allExtensions.contains(ext) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append(url)
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Extract a date string (YYYY-MM-DD) from the filename or file modification date.
    private func extractDate(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent

        // Try DSC_YYYYMMDD or IMG_YYYYMMDD patterns
        let patterns = [
            #"(\d{4})(\d{2})(\d{2})"#,
            #"(\d{4})-(\d{2})-(\d{2})"#
        ]

        for pattern in patterns {
            if let match = name.range(of: pattern, options: .regularExpression) {
                let raw = String(name[match])
                let digits = raw.filter(\.isNumber)
                if digits.count >= 8 {
                    let y = String(digits.prefix(4))
                    let m = String(digits.dropFirst(4).prefix(2))
                    let d = String(digits.dropFirst(6).prefix(2))
                    // Basic sanity check
                    if let yr = Int(y), let mo = Int(m), let dy = Int(d),
                       yr >= 2000, yr <= 2100, mo >= 1, mo <= 12, dy >= 1, dy <= 31 {
                        return "\(y)-\(m)-\(d)"
                    }
                }
            }
        }

        // Fall back to modification date
        if let mdate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            let cal = Calendar.current
            let y = cal.component(.year, from: mdate)
            let m = cal.component(.month, from: mdate)
            let d = cal.component(.day, from: mdate)
            return String(format: "%04d-%02d-%02d", y, m, d)
        }

        return "0000-00-00"
    }

    private func shouldSkip(source: URL, dest: URL, fm: FileManager) -> Bool {
        guard fm.fileExists(atPath: dest.path) else { return false }
        let srcSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let dstSize = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
        return srcSize == dstSize
    }
}
