import Foundation

/// Una tabella del report: intestazione + righe.
struct ReportTable: Sendable {
    var title: String
    var headers: [String]
    var rows: [[String]]
    var note: String? = nil
}

/// Contenuto completo di un report esportabile.
struct ReportDocument: Sendable {
    var title: String
    var generatedAt: Date = Date()
    /// Descrizione del filtro: gioco, ruota, periodo.
    var scope: String
    /// Metodo usato (strategia, pesi, parametri).
    var method: String
    var summaryLines: [String] = []
    var tables: [ReportTable] = []
    var disclaimers: [String] = [Disclaimer.primary, Disclaimer.score]

    var fileBaseName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let safeTitle = title
            .folding(options: [.diacriticInsensitive], locale: Theme.italianLocale)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(safeTitle)-\(formatter.string(from: generatedAt))"
    }
}
