import Foundation

/// Importazione da file o payload JSON.
///
/// Accetta sia un array di oggetti sia un oggetto contenitore con una chiave
/// `draws` / `estrazioni` / `data` / `results`.
enum JSONImporter {

    static func parse(data: Data, defaultGame: GameType) throws -> [DrawRecord] {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let array = try extractArray(from: object)
        var records: [DrawRecord] = []
        records.reserveCapacity(array.count)

        for element in array {
            guard let dictionary = element as? [String: Any] else { continue }
            let row = flatten(dictionary)
            if let record = try DrawParser.record(from: row, defaultGame: defaultGame) {
                records.append(record)
            }
        }
        guard !records.isEmpty else { throw ImportError.emptyFile }
        return records
    }

    private static func extractArray(from object: Any) throws -> [Any] {
        if let array = object as? [Any] { return array }
        if let dictionary = object as? [String: Any] {
            for key in ["draws", "estrazioni", "data", "results", "items", "records"] {
                if let array = dictionary[key] as? [Any] { return array }
            }
            // Struttura annidata: prende il primo array trovato.
            for value in dictionary.values {
                if let array = value as? [Any], !array.isEmpty { return array }
            }
        }
        throw ImportError.unsupportedFormat("json")
    }

    /// Appiattisce un oggetto JSON in coppie stringa → stringa, normalizzando le chiavi.
    private static func flatten(_ dictionary: [String: Any], prefix: String = "") -> [String: String] {
        var row: [String: String] = [:]
        for (key, value) in dictionary {
            let normalized = DrawParser.normalizeKey(prefix.isEmpty ? key : "\(prefix)_\(key)")
            switch value {
            case let string as String:
                row[normalized] = string
            case let number as NSNumber:
                row[normalized] = number.stringValue
            case let array as [Any]:
                let joined = array.compactMap { element -> String? in
                    if let number = element as? NSNumber { return number.stringValue }
                    return element as? String
                }.joined(separator: ",")
                row[normalized] = joined
                // Espone anche i singoli elementi come numero1…numero6.
                let values = array.compactMap { element -> Int? in
                    if let number = element as? NSNumber { return number.intValue }
                    if let string = element as? String { return Int(string) }
                    return nil
                }
                for (index, item) in values.enumerated() where index < 6 {
                    row["numero\(index + 1)"] = String(item)
                }
            case let nested as [String: Any]:
                row.merge(flatten(nested, prefix: key)) { current, _ in current }
            default:
                continue
            }
        }
        return row
    }
}
