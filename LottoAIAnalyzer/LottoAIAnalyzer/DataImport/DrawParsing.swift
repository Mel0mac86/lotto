import Foundation

/// Errori di importazione.
enum ImportError: LocalizedError {
    case unreadableFile(String)
    case unsupportedFormat(String)
    case missingColumns([String])
    case emptyFile
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name): return "Impossibile leggere il file «\(name)»."
        case .unsupportedFormat(let ext): return "Formato non supportato: .\(ext). Sono accettati CSV, JSON, XLSX."
        case .missingColumns(let columns): return "Colonne obbligatorie mancanti: \(columns.joined(separator: ", "))."
        case .emptyFile: return "Il file non contiene righe valide."
        case .network(let detail): return "Errore di rete: \(detail)"
        }
    }
}

/// Traduce righe generiche (dizionari colonna → valore) in `DrawRecord`.
///
/// Accetta le intestazioni più diffuse nei dataset pubblici italiani, sia in
/// italiano sia in inglese, con o senza accenti e maiuscole.
enum DrawParser {

    static let dateKeys = ["data", "date", "data_estrazione", "dataestrazione", "giorno", "drawdate"]
    static let wheelKeys = ["ruota", "wheel", "citta", "città", "ruota_estrazione"]
    static let gameKeys = ["gioco", "game", "concorso_tipo", "tipo"]
    static let jollyKeys = ["jolly", "numerojolly", "numero_jolly"]
    static let superStarKeys = ["superstar", "super_star", "ss"]

    /// Chiavi accettate per l'n-esimo numero (1-based).
    static func numberKeys(_ index: Int) -> [String] {
        ["numero\(index)", "n\(index)", "num\(index)", "estratto\(index)", "number\(index)", "n_\(index)", "numero_\(index)"]
    }

    static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }

    /// Costruisce un record da una riga già normalizzata.
    /// `defaultGame` viene usato quando la riga non specifica il gioco.
    static func record(from row: [String: String], defaultGame: GameType) throws -> DrawRecord? {
        guard let rawDate = firstValue(in: row, keys: dateKeys), let date = parseDate(rawDate) else { return nil }

        let game: GameType
        if let rawGame = firstValue(in: row, keys: gameKeys), let parsed = parseGame(rawGame) {
            game = parsed
        } else {
            game = defaultGame
        }

        let wheel = firstValue(in: row, keys: wheelKeys).flatMap { Wheel.parse($0) }
        if game.usesWheels && wheel == nil { return nil }

        var numbers: [Int] = []
        for index in 1...6 {
            guard let raw = firstValue(in: row, keys: numberKeys(index)),
                  let value = Int(raw.trimmingCharacters(in: .whitespaces)),
                  (1...90).contains(value) else { continue }
            numbers.append(value)
        }
        // Alcuni dataset usano una sola colonna "numeri" con i valori separati.
        if numbers.isEmpty, let combined = firstValue(in: row, keys: ["numeri", "numbers", "estratti", "combinazione"]) {
            numbers = combined
                .components(separatedBy: CharacterSet(charactersIn: " ,;-.|"))
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...90).contains($0) }
        }
        guard numbers.count >= game.drawnCount else { return nil }
        numbers = Array(numbers.prefix(game.drawnCount))

        let jolly = firstValue(in: row, keys: jollyKeys).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let superstar = firstValue(in: row, keys: superStarKeys).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        return DrawRecord(date: date,
                          game: game,
                          wheel: game.usesWheels ? wheel : nil,
                          numbers: numbers,
                          jolly: game.usesJolly ? jolly : nil,
                          superstar: game.usesSuperStar ? superstar : nil)
    }

    static func firstValue(in row: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = row[key], !value.trimmingCharacters(in: .whitespaces).isEmpty { return value }
        }
        return nil
    }

    static func parseGame(_ raw: String) -> GameType? {
        let normalized = normalizeKey(raw)
        if normalized.contains("super") { return .superenalotto }
        if normalized.contains("lotto") { return .lotto }
        return nil
    }

    /// Formati data accettati, provati nell'ordine.
    static let dateFormats = [
        "yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy", "dd.MM.yyyy",
        "yyyy/MM/dd", "MM/dd/yyyy", "yyyyMMdd", "yyyy-MM-dd'T'HH:mm:ss"
    ]

    private static let formatters: [DateFormatter] = dateFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = format
        return formatter
    }

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) { return normalizeToNoon(date) }
        }
        if let iso = ISO8601DateFormatter().date(from: trimmed) { return normalizeToNoon(iso) }
        // Timestamp Unix in secondi.
        if let seconds = TimeInterval(trimmed), seconds > 100_000_000 {
            return normalizeToNoon(Date(timeIntervalSince1970: seconds))
        }
        // Numero seriale Excel (giorni dal 30/12/1899). L'intervallo utile copre 1954–2064.
        if let serial = Double(trimmed), serial > 20_000, serial < 60_000 {
            var components = DateComponents()
            components.year = 1899; components.month = 12; components.day = 30
            if let epoch = Calendar.italian.date(from: components),
               let date = Calendar.italian.date(byAdding: .day, value: Int(serial), to: epoch) {
                return normalizeToNoon(date)
            }
        }
        return nil
    }

    /// Riporta la data a mezzogiorno (ora italiana) per evitare che i cambi di
    /// fuso orario spostino un'estrazione al giorno precedente o successivo.
    static func normalizeToNoon(_ date: Date) -> Date {
        var components = Calendar.italian.dateComponents([.year, .month, .day], from: date)
        components.hour = 12
        components.minute = 0
        components.second = 0
        return Calendar.italian.date(from: components) ?? date
    }
}
