import AppKit
import ImageIO

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let thumbCache = NSCache<NSURL, NSImage>()
    private let previewCache = NSCache<NSURL, NSImage>()

    init() {
        thumbCache.countLimit = 500
        thumbCache.totalCostLimit = 100 * 1024 * 1024   // 100 MB
        previewCache.countLimit = 100
        previewCache.totalCostLimit = 300 * 1024 * 1024  // 300 MB
    }

    /// Load a thumbnail for the given URL at the requested size.
    /// - Parameters:
    ///   - url: File URL of the image.
    ///   - size: Maximum dimension in points (e.g. 400 for thumb, 1200 for preview).
    /// - Returns: NSImage or nil if loading failed.
    func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let cache = previewCache
        let key = url as NSURL

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(size)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let cost = cgImage.width * cgImage.height * 4
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Invalidate cached entries for a URL (e.g. after metadata write).
    func invalidate(url: URL) {
        let key = url as NSURL
        thumbCache.removeObject(forKey: key)
        previewCache.removeObject(forKey: key)
    }

    /// Purge all caches.
    func purgeAll() {
        thumbCache.removeAllObjects()
        previewCache.removeAllObjects()
    }
}
