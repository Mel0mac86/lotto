import Foundation

/// Sceglie il parser corretto in base all'estensione o al contenuto del file.
enum ImportCoordinator {

    static func parse(fileURL: URL, defaultGame: GameType) throws -> [DrawRecord] {
        let needsScopedAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScopedAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ImportError.unreadableFile(fileURL.lastPathComponent)
        }
        return try parse(data: data,
                         fileExtension: fileURL.pathExtension.lowercased(),
                         defaultGame: defaultGame)
    }

    static func parse(data: Data, fileExtension: String, defaultGame: GameType) throws -> [DrawRecord] {
        switch fileExtension {
        case "csv", "txt", "tsv":
            return try CSVImporter.parse(data: data, defaultGame: defaultGame)
        case "json":
            return try JSONImporter.parse(data: data, defaultGame: defaultGame)
        case "xlsx", "xlsm":
            return try XLSXImporter.parse(data: data, defaultGame: defaultGame)
        case "xls":
            // I vecchi .xls binari non sono supportati: si suggerisce la conversione.
            throw ImportError.unsupportedFormat("xls (converti in .xlsx o .csv)")
        default:
            return try parseByContent(data: data, defaultGame: defaultGame, fallbackExtension: fileExtension)
        }
    }

    /// Rileva il formato dai primi byte quando l'estensione è assente o generica.
    static func parseByContent(data: Data, defaultGame: GameType, fallbackExtension: String = "") throws -> [DrawRecord] {
        let prefix = data.prefix(4)
        if prefix.starts(with: [0x50, 0x4B]) { // "PK" — archivio ZIP, quindi xlsx
            return try XLSXImporter.parse(data: data, defaultGame: defaultGame)
        }
        if let text = CSVImporter.decode(data) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                return try JSONImporter.parse(data: data, defaultGame: defaultGame)
            }
            return try CSVImporter.parse(text: text, defaultGame: defaultGame)
        }
        throw ImportError.unsupportedFormat(fallbackExtension.isEmpty ? "sconosciuto" : fallbackExtension)
    }
}
