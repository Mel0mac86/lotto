import Foundation

/// Sorgente remota configurabile dall'utente.
///
/// L'app non incorpora né promuove alcuna fonte specifica: l'utente inserisce
/// l'URL di un servizio che ha il diritto di utilizzare (API ufficiale, open data,
/// proprio export). Il servizio scarica, riconosce il formato e deduplica.
struct RemoteSource: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var urlString: String
    var game: GameType
    var isEnabled: Bool = true
    /// Header HTTP opzionali (per esempio una chiave API).
    var headers: [String: String] = [:]

    var url: URL? { URL(string: urlString) }
}

/// Scarica le estrazioni da una sorgente remota.
struct RemoteDataService: Sendable {

    var session: URLSession = .shared

    func fetch(_ source: RemoteSource) async throws -> [DrawRecord] {
        guard let url = source.url else { throw ImportError.network("URL non valido: \(source.urlString)") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in source.headers { request.setValue(value, forHTTPHeaderField: key) }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ImportError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ImportError.network("Risposta HTTP \(http.statusCode)")
        }

        let contentType = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("json") {
            return try JSONImporter.parse(data: data, defaultGame: source.game)
        }
        if contentType.contains("csv") || contentType.contains("text/plain") {
            return try CSVImporter.parse(data: data, defaultGame: source.game)
        }
        if contentType.contains("spreadsheet") || contentType.contains("excel") {
            return try XLSXImporter.parse(data: data, defaultGame: source.game)
        }
        return try ImportCoordinator.parseByContent(data: data, defaultGame: source.game)
    }
}
