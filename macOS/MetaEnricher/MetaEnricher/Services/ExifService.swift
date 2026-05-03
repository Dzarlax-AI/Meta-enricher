import Foundation
import ImageIO

// MARK: - MetaWrite

struct MetaWrite: Sendable {
    var title: String?
    var description: String?
    var keywords: [String]?
    var city: String?
    var country: String?
    var rating: Int?
    var creator: String?
    var copyright: String?
    var gpsLat: Double?
    var gpsLon: Double?
}

// MARK: - ExifService

actor ExifService {
    static let shared = ExifService()

    // MARK: - Reading via ImageIO

    func readMeta(from url: URL) async -> PhotoMeta {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return PhotoMeta() }

        var meta = PhotoMeta()

        // EXIF
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            if let fn = exif[kCGImagePropertyExifFNumber] as? Double {
                meta.aperture = String(format: "f/%.1f", fn)
            }
            if let et = exif[kCGImagePropertyExifExposureTime] as? Double {
                if et >= 1 {
                    meta.shutterSpeed = String(format: "%.0fs", et)
                } else {
                    let denom = Int((1.0 / et).rounded())
                    meta.shutterSpeed = "1/\(denom)s"
                }
            }
            if let isoArr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArr.first {
                meta.iso = iso
            } else if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
                meta.iso = iso
            }
            if let fl = exif[kCGImagePropertyExifFocalLength] as? Double {
                meta.focalLength = String(format: "%.0fmm", fl)
            }
            if let lens = exif[kCGImagePropertyExifLensModel] as? String {
                // stored separately; use model fallback below
                _ = lens
            }
        }

        // IPTC
        if let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            meta.title       = iptc[kCGImagePropertyIPTCObjectName] as? String
            meta.description = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String
            if let kws = iptc[kCGImagePropertyIPTCKeywords] as? [String] {
                meta.keywords = kws
            } else if let kw = iptc[kCGImagePropertyIPTCKeywords] as? String {
                meta.keywords = [kw]
            }
            let city    = iptc[kCGImagePropertyIPTCCity] as? String
            let country = iptc[kCGImagePropertyIPTCCountryPrimaryLocationName] as? String
            if let city, let country {
                meta.location = "\(city), \(country)"
            } else {
                meta.location = city ?? country
            }
        }

        // GPS
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String {
                meta.gpsLat = latRef == "S" ? -lat : lat
            }
            if let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                meta.gpsLon = lonRef == "W" ? -lon : lon
            }
        }

        // TIFF
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.make      = tiff[kCGImagePropertyTIFFMake] as? String
            meta.model     = tiff[kCGImagePropertyTIFFModel] as? String
            meta.creator   = tiff[kCGImagePropertyTIFFArtist] as? String
            meta.copyright = tiff[kCGImagePropertyTIFFCopyright] as? String
        }

        // XMP (rating, title/description fallback)
        if let xmp = props["XMP" as CFString] as? [CFString: Any] {
            if let rating = xmp["Rating" as CFString] as? Int {
                meta.rating = rating
            }
            if meta.title == nil {
                meta.title = (xmp["dc:title" as CFString] as? [String: String])?["x-default"]
                    ?? xmp["dc:title" as CFString] as? String
            }
            if meta.description == nil {
                meta.description = (xmp["dc:description" as CFString] as? [String: String])?["x-default"]
                    ?? xmp["dc:description" as CFString] as? String
            }
            if meta.keywords.isEmpty {
                if let subj = xmp["dc:subject" as CFString] as? [String] {
                    meta.keywords = subj
                }
            }
        }

        return meta
    }

    // MARK: - Batch Reading via exiftool

    /// Read metadata for multiple files in a single exiftool invocation.
    func readMetaBatch(urls: [URL]) async -> [URL: PhotoMeta] {
        guard !urls.isEmpty else { return [:] }

        var args = ["-json", "-n",
                    "-Title", "-Description", "-Keywords",
                    "-City", "-Country", "-Rating",
                    "-Creator", "-Copyright",
                    "-DateTimeOriginal", "-Make", "-Model",
                    "-FocalLength", "-Aperture", "-ShutterSpeed", "-ISO",
                    "-GPSLatitude", "-GPSLongitude", "-GPSLatitudeRef", "-GPSLongitudeRef"]
        args += urls.map(\.path)

        let exiftoolPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/exiftool") ? "/opt/homebrew/bin/exiftool" : "/usr/local/bin/exiftool"
        guard let data = try? await runProcess(exiftoolPath, args: args) else {
            // fallback: read individually via ImageIO
            var result: [URL: PhotoMeta] = [:]
            for url in urls {
                result[url] = await readMeta(from: url)
            }
            return result
        }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            var result: [URL: PhotoMeta] = [:]
            for url in urls { result[url] = await readMeta(from: url) }
            return result
        }

        var result: [URL: PhotoMeta] = [:]
        for (index, dict) in jsonArray.enumerated() {
            guard index < urls.count else { break }
            let url = urls[index]
            result[url] = parseExiftoolDict(dict)
        }
        return result
    }

    // MARK: - Writing via CGImageDestination (native, no exiftool, lossless)

    func writeMeta(to url: URL, meta: MetaWrite) async throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ExifError.writeFailed("Cannot open image: \(url.lastPathComponent)")
        }
        let uti = CGImageSourceGetType(source) ?? ("public.jpeg" as CFString)

        let md = mutableMetadata(from: source)

        // IPTC
        if let v = meta.title       { setIPTC(md, kCGImagePropertyIPTCObjectName,                   v as CFString) }
        if let v = meta.description { setIPTC(md, kCGImagePropertyIPTCCaptionAbstract,              v as CFString) }
        if let v = meta.keywords, !v.isEmpty { setIPTC(md, kCGImagePropertyIPTCKeywords,            v as CFArray)  }
        if let v = meta.city        { setIPTC(md, kCGImagePropertyIPTCCity,                         v as CFString) }
        if let v = meta.country     { setIPTC(md, kCGImagePropertyIPTCCountryPrimaryLocationName,   v as CFString) }
        if let v = meta.creator     { setIPTC(md, kCGImagePropertyIPTCByline,                       v as CFString) }
        if let v = meta.copyright   { setIPTC(md, kCGImagePropertyIPTCCopyrightNotice,              v as CFString) }

        // TIFF
        if let v = meta.creator     { setTIFF(md, kCGImagePropertyTIFFArtist,                       v as CFString) }
        if let v = meta.copyright   { setTIFF(md, kCGImagePropertyTIFFCopyright,                    v as CFString) }

        // XMP (Dublin Core + xmp:Rating)
        if let v = meta.title       { setXMPString(md, ns: kCGImageMetadataNamespaceDublinCore,    prefix: "dc",  name: "title",       value: v) }
        if let v = meta.description { setXMPString(md, ns: kCGImageMetadataNamespaceDublinCore,    prefix: "dc",  name: "description", value: v) }
        if let v = meta.keywords, !v.isEmpty {
                                      setXMPArray (md, ns: kCGImageMetadataNamespaceDublinCore,    prefix: "dc",  name: "subject",     values: v) }
        if let v = meta.creator     { setXMPArray (md, ns: kCGImageMetadataNamespaceDublinCore,    prefix: "dc",  name: "creator",     values: [v]) }
        if let v = meta.copyright   { setXMPString(md, ns: kCGImageMetadataNamespaceDublinCore,    prefix: "dc",  name: "rights",      value: v) }
        if let v = meta.rating      { setXMPString(md, ns: kCGImageMetadataNamespaceXMPBasic,      prefix: "xmp", name: "Rating",      value: "\(v)") }

        // GPS
        if let lat = meta.gpsLat, let lon = meta.gpsLon {
            setGPS(md, kCGImagePropertyGPSLatitude,    abs(lat) as CFNumber)
            setGPS(md, kCGImagePropertyGPSLatitudeRef, (lat >= 0 ? "N" : "S") as CFString)
            setGPS(md, kCGImagePropertyGPSLongitude,   abs(lon) as CFNumber)
            setGPS(md, kCGImagePropertyGPSLongitudeRef,(lon >= 0 ? "E" : "W") as CFString)
        }

        try losslessWrite(source: source, uti: uti, metadata: md, to: url)
    }

    /// Update EXIF orientation flag only — pixels stay untouched.
    func rotateOrientation(url: URL, clockwise: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ExifError.writeFailed("Cannot open image: \(url.lastPathComponent)")
        }
        let uti = CGImageSourceGetType(source) ?? ("public.jpeg" as CFString)
        let md  = mutableMetadata(from: source)

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let current = (props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFOrientation] as? Int ?? 1
        let next = rotatedExifOrientation(current, clockwise: clockwise)

        setTIFF(md, kCGImagePropertyTIFFOrientation, next as CFNumber)

        try losslessWrite(source: source, uti: uti, metadata: md, to: url)
    }

    // MARK: - Helpers

    // MARK: - CGImageMetadata helpers

    private func mutableMetadata(from source: CGImageSource) -> CGMutableImageMetadata {
        if let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
           let copy = CGImageMetadataCreateMutableCopy(existing) { return copy }
        return CGImageMetadataCreateMutable()
    }

    private func setIPTC(_ md: CGMutableImageMetadata, _ key: CFString, _ val: CFTypeRef) {
        _ = CGImageMetadataSetValueMatchingImageProperty(md, kCGImagePropertyIPTCDictionary, key, val)
    }
    private func setTIFF(_ md: CGMutableImageMetadata, _ key: CFString, _ val: CFTypeRef) {
        _ = CGImageMetadataSetValueMatchingImageProperty(md, kCGImagePropertyTIFFDictionary, key, val)
    }
    private func setGPS(_ md: CGMutableImageMetadata, _ key: CFString, _ val: CFTypeRef) {
        _ = CGImageMetadataSetValueMatchingImageProperty(md, kCGImagePropertyGPSDictionary, key, val)
    }

    private func setXMPString(_ md: CGMutableImageMetadata, ns: CFString, prefix: String, name: String, value: String) {
        guard let tag = CGImageMetadataTagCreate(ns, prefix as CFString, name as CFString, .string, value as CFTypeRef) else { return }
        _ = CGImageMetadataSetTagWithPath(md, nil, "\(prefix):\(name)" as CFString, tag)
    }

    private func setXMPArray(_ md: CGMutableImageMetadata, ns: CFString, prefix: String, name: String, values: [String]) {
        guard let tag = CGImageMetadataTagCreate(ns, prefix as CFString, name as CFString, .arrayUnordered, values as CFTypeRef) else { return }
        _ = CGImageMetadataSetTagWithPath(md, nil, "\(prefix):\(name)" as CFString, tag)
    }

    private func losslessWrite(source: CGImageSource, uti: CFString, metadata: CGMutableImageMetadata, to url: URL) throws {
        let tmp = url.deletingLastPathComponent()
                     .appendingPathComponent(".\(url.lastPathComponent).me-tmp")
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, uti, 1, nil) else {
            throw ExifError.writeFailed("Cannot create destination for \(url.lastPathComponent)")
        }
        var cfErr: Unmanaged<CFError>?
        let opts: [CFString: Any] = [kCGImageDestinationMergeMetadata: true,
                                     kCGImageDestinationMetadata: metadata]
        guard CGImageDestinationCopyImageSource(dest, source, opts as CFDictionary, &cfErr) else {
            throw ExifError.writeFailed(cfErr?.takeRetainedValue().localizedDescription ?? "Copy failed")
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// EXIF orientation CW/CCW lookup (values 1–8, mirrored variants preserved).
    private func rotatedExifOrientation(_ current: Int, clockwise: Bool) -> Int {
        let cw:  [Int: Int] = [1:6, 6:3, 3:8, 8:1, 2:7, 7:4, 4:5, 5:2]
        let ccw: [Int: Int] = [1:8, 8:3, 3:6, 6:1, 2:5, 5:4, 4:7, 7:2]
        return (clockwise ? cw : ccw)[current] ?? 1
    }

    // MARK: - Process runner (used by readMetaBatch with exiftool fallback)

    @discardableResult
    private func runProcess(_ executable: String, args: [String]) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = args

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: data)
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "unknown error"
                    continuation.resume(throwing: ExifError.exiftoolFailed(msg))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseExiftoolDict(_ dict: [String: Any]) -> PhotoMeta {
        var meta = PhotoMeta()
        meta.title            = dict["Title"] as? String
        meta.description      = dict["Description"] as? String
        if let kws = dict["Keywords"] as? [String] {
            meta.keywords = kws
        } else if let kw = dict["Keywords"] as? String {
            meta.keywords = [kw]
        }
        let city    = dict["City"] as? String
        let country = dict["Country"] as? String
        if let city, let country {
            meta.location = "\(city), \(country)"
        } else {
            meta.location = city ?? country
        }
        meta.rating           = dict["Rating"] as? Int
        meta.creator          = dict["Creator"] as? String
        meta.copyright        = dict["Copyright"] as? String
        meta.dateTimeOriginal = dict["DateTimeOriginal"] as? String
        meta.make             = dict["Make"] as? String
        meta.model            = dict["Model"] as? String
        if let fl = dict["FocalLength"] as? Double {
            meta.focalLength = String(format: "%.0fmm", fl)
        }
        if let ap = dict["Aperture"] as? Double {
            meta.aperture = String(format: "f/%.1f", ap)
        }
        if let ss = dict["ShutterSpeed"] as? Double {
            if ss >= 1 {
                meta.shutterSpeed = String(format: "%.0fs", ss)
            } else {
                let denom = Int((1.0 / ss).rounded())
                meta.shutterSpeed = "1/\(denom)s"
            }
        } else if let ss = dict["ShutterSpeed"] as? String {
            meta.shutterSpeed = ss
        }
        meta.iso              = dict["ISO"] as? Int
        if let lat = dict["GPSLatitude"] as? Double,
           let lon = dict["GPSLongitude"] as? Double {
            meta.gpsLat = lat
            meta.gpsLon = lon
        }
        return meta
    }
}

// MARK: - Errors

enum ExifError: LocalizedError {
    case exiftoolFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .exiftoolFailed(let msg): return "exiftool error: \(msg)"
        case .writeFailed(let msg):    return "Write error: \(msg)"
        }
    }
}
