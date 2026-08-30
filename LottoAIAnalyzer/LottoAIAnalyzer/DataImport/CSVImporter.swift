import Foundation

/// Importazione da file CSV / TSV.
///
/// Il parser gestisce virgolette, campi multilinea e separatori `,` `;` `\t`,
/// rilevati automaticamente dall'intestazione.
enum CSVImporter {

    static func parse(data: Data, defaultGame: GameType) throws -> [DrawRecord] {
        guard let text = decode(data) else { throw ImportError.unreadableFile("CSV") }
        return try parse(text: text, defaultGame: defaultGame)
    }

    static func parse(text: String, defaultGame: GameType) throws -> [DrawRecord] {
        let separator = detectSeparator(in: text)
        let rows = parseRows(text: text, separator: separator)
        guard let header = rows.first, rows.count > 1 else { throw ImportError.emptyFile }

        let keys = header.map { DrawParser.normalizeKey($0) }
        var records: [DrawRecord] = []
        records.reserveCapacity(rows.count - 1)

        for row in rows.dropFirst() {
            guard row.count >= 2 else { continue }
            var dictionary: [String: String] = [:]
            for (index, key) in keys.enumerated() where index < row.count {
                dictionary[key] = row[index]
            }
            if let record = try DrawParser.record(from: dictionary, defaultGame: defaultGame) {
                records.append(record)
            }
        }
        guard !records.isEmpty else { throw ImportError.emptyFile }
        return records
    }

    static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        return String(data: data, encoding: .windowsCP1252)
    }

    static func detectSeparator(in text: String) -> Character {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let candidates: [Character] = [";", ",", "\t", "|"]
        var best: (Character, Int) = (",", 0)
        for candidate in candidates {
            let count = firstLine.filter { $0 == candidate }.count
            if count > best.1 { best = (candidate, count) }
        }
        return best.0
    }

    /// Parser CSV conforme a RFC 4180 (virgolette doppie, campi multilinea).
    static func parseRows(text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func finishField() {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            currentField = ""
        }
        func finishRow() {
            finishField()
            if currentRow.contains(where: { !$0.isEmpty }) { rows.append(currentRow) }
            currentRow = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if insideQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { currentField.append("\"") } else { insideQuotes = false; pending = next }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                insideQuotes = true
            case separator:
                finishField()
            case "\n":
                finishRow()
            case "\r":
                break
            default:
                currentField.append(character)
            }
        }
        if !currentField.isEmpty || !currentRow.isEmpty { finishRow() }
        return rows
    }
}
