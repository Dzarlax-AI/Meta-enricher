import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - OllamaService

actor OllamaService {
    static let shared = OllamaService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    // MARK: - Connectivity

    /// Returns true if the Ollama server is reachable and has at least one model.
    func checkOllama(baseURL: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Returns the list of available model names from the Ollama server.
    func listModels(baseURL: String) async -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return decoded.models.map(\.name).sorted()
        } catch {
            return []
        }
    }

    // MARK: - Model Pull

    struct PullProgress: Sendable {
        var status: String = ""
        var total: Int64   = 0
        var completed: Int64 = 0
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : -1 }
        var isDone: Bool   { status == "success" }
        var isError: Bool  { status.hasPrefix("error") }
    }

    func pullModel(
        name: String,
        baseURL: String,
        onProgress: @Sendable @escaping (PullProgress) -> Void
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/pull") else { throw OllamaError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        request.timeoutInterval = 3600 // large models take a while

        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        var buffer = ""
        for try await byte in bytes {
            let ch = Character(UnicodeScalar(byte))
            if ch == "\n" {
                let line = buffer.trimmingCharacters(in: .whitespaces)
                buffer = ""
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                var prog = PullProgress()
                prog.status    = dict["status"] as? String ?? ""
                prog.total     = (dict["total"]     as? Int64) ?? Int64(dict["total"]     as? Int ?? 0)
                prog.completed = (dict["completed"] as? Int64) ?? Int64(dict["completed"] as? Int ?? 0)
                onProgress(prog)

                if prog.isDone || prog.isError { break }
            } else {
                buffer.append(ch)
            }
        }
    }

    // MARK: - Enrichment

    /// Enrich a photo using the Ollama vision model.
    func enrichPhoto(
        imageURL: URL,
        baseURL: String,
        model: String,
        sessionNotes: String,
        existingMeta: PhotoMeta = PhotoMeta(),
        fields: Set<EnrichField> = Set(EnrichField.allCases)
    ) async throws -> PhotoMeta {
        let imageData = try resizeImage(at: imageURL, maxDimension: 1280)
        let base64 = imageData.base64EncodedString()

        // Context note from photographer
        let contextNote = sessionNotes.isEmpty
            ? ""
            : "\nContext from the photographer: \(sessionNotes)"

        // Context from existing metadata for fields we're NOT regenerating
        var existingLines: [String] = []
        if !fields.contains(.title),       let t = existingMeta.title,       !t.isEmpty { existingLines.append("- Title: \(t)") }
        if !fields.contains(.description), let d = existingMeta.description, !d.isEmpty { existingLines.append("- Description: \(d)") }
        if !fields.contains(.keywords),    !existingMeta.keywords.isEmpty               { existingLines.append("- Keywords: \(existingMeta.keywords.joined(separator: ", "))") }
        if !fields.contains(.location),    let l = existingMeta.location,    !l.isEmpty { existingLines.append("- Location: \(l)") }
        let existingContext = existingLines.isEmpty ? "" :
            "\nExisting metadata (use as context for consistency):\n\(existingLines.joined(separator: "\n"))\n"

        // Build JSON structure for only the requested fields
        var jsonFields: [String] = []
        if fields.contains(.title)       { jsonFields.append("  \"title\": \"short descriptive title (max 80 chars)\"") }
        if fields.contains(.description) { jsonFields.append("  \"description\": \"one to three sentence description\"") }
        if fields.contains(.keywords)    { jsonFields.append("  \"keywords\": [\"keyword1\", \"keyword2\", ...]") }
        if fields.contains(.location)    { jsonFields.append("  \"city\": \"city name or null\""); jsonFields.append("  \"country\": \"country name or null\"") }
        let jsonStructure = "{\n\(jsonFields.joined(separator: ",\n"))\n}"

        // Rules for each requested field
        var rules: [String] = []
        if fields.contains(.title)       { rules.append("- title: concise, evocative, no camera settings") }
        if fields.contains(.description) { rules.append("- description: describe subject, mood, composition") }
        if fields.contains(.keywords)    { rules.append("- keywords: 5-10 relevant tags (subjects, style, mood, colors, genre)") }
        if fields.contains(.location)    { rules.append("- city/country: best guess from visual cues (architecture, signage, landscape), null if truly uncertain") }

        let prompt = """
        Analyze this photo and respond ONLY with a JSON object (no markdown fences, no extra text).\(contextNote)\(existingContext)

        Respond with exactly this structure:
        \(jsonStructure)

        Rules:
        \(rules.joined(separator: "\n"))
        """

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "images": [base64],
            "stream": false,
            "format": "json",
            "think": false          // disable Qwen3 thinking mode (ignored by other models)
        ]

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.badResponse(body)
        }

        let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)

        // qwen3 models put the answer in "thinking" when think mode is active
        let rawText: String
        if !generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawText = generateResponse.response
        } else if let thinking = generateResponse.thinking,
                  !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[OllamaService] ℹ️ Using 'thinking' field as response (qwen3 behaviour)")
            rawText = thinking
        } else {
            let fullBody = String(data: data, encoding: .utf8) ?? "<unreadable>"
            print("[OllamaService] ⚠️ Empty response field. Full Ollama response:\n\(fullBody)")
            rawText = ""
        }

        return try parseMetaJSON(rawText)
    }

    // MARK: - Image Resizing

    nonisolated private func resizeImage(at url: URL, maxDimension: CGFloat) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OllamaError.imageLoadFailed
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw OllamaError.imageLoadFailed
        }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else {
            throw OllamaError.imageLoadFailed
        }

        let destOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(dest, cgImage, destOptions as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw OllamaError.imageLoadFailed
        }

        return mutableData as Data
    }

    // MARK: - JSON Parsing

    nonisolated private func parseMetaJSON(_ raw: String) throws -> PhotoMeta {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[OllamaService] ⚠️ Model returned an empty response — model may still be loading or ran out of context.")
            throw OllamaError.parseError("Empty response from model")
        }

        // Strip Qwen3 thinking blocks <think>...</think> if present
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thinkStart = text.range(of: "<think>"),
           let thinkEnd   = text.range(of: "</think>") {
            text.removeSubrange(thinkStart.lowerBound...thinkEnd.upperBound)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
            let stripped = lines.dropFirst().dropLast()
            text = stripped.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find the JSON object bounds
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }

        guard let data = text.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[OllamaService] ⚠️ Failed to parse AI response. Raw text:\n\(raw)")
            throw OllamaError.parseError(raw)
        }

        var meta = PhotoMeta()
        meta.title       = dict["title"] as? String
        meta.description = dict["description"] as? String
        if let kws = dict["keywords"] as? [String] {
            // Deduplicate preserving order
            var seen = Set<String>()
            meta.keywords = kws.filter { seen.insert($0.lowercased()).inserted }
        }

        let city    = dict["city"] as? String
        let country = dict["country"] as? String
        switch (city, country) {
        case let (c?, co?): meta.location = "\(c), \(co)"
        case let (c?, nil): meta.location = c
        case let (nil, co?): meta.location = co
        default: break
        }
        meta.locationSource = "ai"

        return meta
    }
}

// MARK: - Response Models

private struct OllamaTagsResponse: Decodable, Sendable {
    struct Model: Decodable, Sendable { let name: String }
    let models: [Model]
}

private struct OllamaGenerateResponse: Decodable, Sendable {
    let response: String
    let thinking: String?
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case invalidURL
    case badResponse(String)
    case imageLoadFailed
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid Ollama URL"
        case .badResponse(let s): return "Ollama bad response: \(s)"
        case .imageLoadFailed:    return "Failed to load/resize image"
        case .parseError(let s):  return "Failed to parse AI response: \(s)"
        }
    }
}
