import Foundation

actor GeocodingService {
    static let shared = GeocodingService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// Reverse geocode a coordinate using OpenStreetMap Nominatim.
    /// - Returns: A tuple of (city, country) where either may be nil.
    func reverseGeocode(lat: Double, lon: Double) async -> (city: String?, country: String?) {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        components.queryItems = [
            URLQueryItem(name: "lat",    value: String(lat)),
            URLQueryItem(name: "lon",    value: String(lon)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "zoom",   value: "10"),
            URLQueryItem(name: "addressdetails", value: "1")
        ]
        guard let url = components.url else { return (nil, nil) }

        var request = URLRequest(url: url)
        request.setValue("MetaEnricher/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, nil) }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let address = json["address"] as? [String: Any]
            else { return (nil, nil) }

            let city = address["city"] as? String
                    ?? address["town"] as? String
                    ?? address["village"] as? String
                    ?? address["municipality"] as? String
                    ?? address["county"] as? String

            let country = address["country"] as? String

            return (city, country)
        } catch {
            return (nil, nil)
        }
    }
}
