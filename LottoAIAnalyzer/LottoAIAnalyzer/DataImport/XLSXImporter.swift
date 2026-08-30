import Foundation

/// Importazione da file Excel `.xlsx`.
///
/// Il file viene aperto come archivio ZIP; vengono letti `xl/sharedStrings.xml`
/// e il primo foglio (`xl/worksheets/sheet1.xml`). La prima riga è l'intestazione.
enum XLSXImporter {

    static func parse(data: Data, defaultGame: GameType) throws -> [DrawRecord] {
        let archive = try ZIPArchive(data: data)
        let sharedStrings = try archive.extract("xl/sharedStrings.xml").map { SharedStringsParser.parse($0) } ?? []

        let sheetName = archive.entries
            .map(\.name)
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()
            .first ?? "xl/worksheets/sheet1.xml"
        guard let sheetData = try archive.extract(sheetName) else {
            throw ImportError.unreadableFile(sheetName)
        }

        let rows = SheetParser.parse(sheetData, sharedStrings: sharedStrings)
        guard let header = rows.first, rows.count > 1 else { throw ImportError.emptyFile }
        let keys = header.map { DrawParser.normalizeKey($0) }

        var records: [DrawRecord] = []
        for row in rows.dropFirst() {
            var dictionary: [String: String] = [:]
            for (index, key) in keys.enumerated() where index < row.count && !key.isEmpty {
                dictionary[key] = row[index]
            }
            if let record = try DrawParser.record(from: dictionary, defaultGame: defaultGame) {
                records.append(record)
            }
        }
        guard !records.isEmpty else { throw ImportError.emptyFile }
        return records
    }
}

/// Estrae la tabella delle stringhe condivise di un file xlsx.
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var insideText = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "si" { current = "" }
        if elementName == "t" { insideText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "t" { insideText = false }
        if elementName == "si" { strings.append(current) }
    }
}

/// Estrae le celle di un foglio xlsx tenendo conto delle colonne vuote.
private final class SheetParser: NSObject, XMLParserDelegate {
    private var rows: [[String]] = []
    private var currentRow: [String] = []
    private var currentValue = ""
    private var currentType = ""
    private var currentColumnIndex = 0
    private var insideValue = false
    private var insideInlineText = false
    private var sharedStrings: [String] = []

    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = SheetParser()
        delegate.sharedStrings = sharedStrings
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    /// Converte il riferimento di cella ("BC12") nell'indice di colonna 0-based.
    private static func columnIndex(from reference: String) -> Int {
        var index = 0
        for character in reference {
            guard let ascii = character.asciiValue else { break }
            if ascii >= 65 && ascii <= 90 {
                index = index * 26 + Int(ascii - 64)
            } else if ascii >= 97 && ascii <= 122 {
                index = index * 26 + Int(ascii - 96)
            } else {
                break
            }
        }
        return max(index - 1, 0)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = []
        case "c":
            currentType = attributes["t"] ?? ""
            currentColumnIndex = Self.columnIndex(from: attributes["r"] ?? "")
            currentValue = ""
        case "v":
            insideValue = true
        case "t":
            insideInlineText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideValue || insideInlineText { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v":
            insideValue = false
        case "t":
            insideInlineText = false
        case "c":
            var value = currentValue
            if currentType == "s", let index = Int(currentValue), index < sharedStrings.count {
                value = sharedStrings[index]
            }
            // Riempie le colonne saltate (celle vuote non emesse da Excel).
            while currentRow.count < currentColumnIndex { currentRow.append("") }
            currentRow.append(value)
            currentValue = ""
        case "row":
            if currentRow.contains(where: { !$0.isEmpty }) { rows.append(currentRow) }
            currentRow = []
        default:
            break
        }
    }
}
