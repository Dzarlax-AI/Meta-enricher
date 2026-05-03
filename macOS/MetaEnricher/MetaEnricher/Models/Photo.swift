import Foundation

struct PhotoSession: Identifiable, Hashable, Sendable {
    let id: String
    let folderURL: URL
    let dateString: String   // e.g. "2026-03-07"
    let label: String?       // optional suffix, e.g. "Fireworks"
    var editedCount: Int
    var originalsCount: Int
    var enrichedCount: Int

    var displayName: String {
        if let label, !label.isEmpty { return "\(dateString) \(label)" }
        return dateString
    }
}

struct Photo: Identifiable, Hashable, Sendable {
    let id: String           // absolute path string
    let url: URL
    var meta: PhotoMeta
    var isEnriched: Bool { meta.title != nil && meta.description != nil }
    var hasPartialMeta: Bool { meta.title != nil || !meta.keywords.isEmpty }
}

// MARK: - Session Enrichment Status

enum SessionEnrichmentStatus: Sendable {
    case unknown, pending, partial, enriched

    var icon: String {
        switch self {
        case .unknown:  "circle.dashed"
        case .pending:  "circle"
        case .partial:  "circle.lefthalf.filled"
        case .enriched: "checkmark.circle.fill"
        }
    }
}

// MARK: - EnrichField

enum EnrichField: String, CaseIterable, Hashable, Sendable {
    case title, description, keywords, location

    var displayName: String {
        switch self {
        case .title:       "Title"
        case .description: "Description"
        case .keywords:    "Keywords"
        case .location:    "Location"
        }
    }
}

// MARK: - PhotoMeta

struct PhotoMeta: Codable, Hashable, Sendable {
    var title: String?
    var description: String?
    var keywords: [String] = []
    var location: String?
    var locationSource: String?    // "gps" | "ai"
    var dateTimeOriginal: String?
    var make: String?
    var model: String?
    var focalLength: String?
    var aperture: String?
    var shutterSpeed: String?
    var iso: Int?
    var rating: Int?
    var creator: String?
    var copyright: String?
    var gpsLat: Double?
    var gpsLon: Double?
}
