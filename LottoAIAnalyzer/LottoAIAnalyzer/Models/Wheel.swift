import Foundation

/// Le ruote del Lotto italiano.
enum Wheel: String, Codable, CaseIterable, Identifiable, Sendable {
    case bari = "Bari"
    case cagliari = "Cagliari"
    case firenze = "Firenze"
    case genova = "Genova"
    case milano = "Milano"
    case napoli = "Napoli"
    case palermo = "Palermo"
    case roma = "Roma"
    case torino = "Torino"
    case venezia = "Venezia"
    case nazionale = "Nazionale"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Sigla breve usata in tabelle e heatmap.
    var shortCode: String {
        switch self {
        case .bari: return "BA"
        case .cagliari: return "CA"
        case .firenze: return "FI"
        case .genova: return "GE"
        case .milano: return "MI"
        case .napoli: return "NA"
        case .palermo: return "PA"
        case .roma: return "RM"
        case .torino: return "TO"
        case .venezia: return "VE"
        case .nazionale: return "NZ"
        }
    }

    /// Riconosce una ruota a partire da una stringa proveniente da un file importato.
    static func parse(_ raw: String) -> Wheel? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
        if normalized.isEmpty { return nil }
        for wheel in Wheel.allCases {
            let candidate = wheel.rawValue.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                                   locale: Locale(identifier: "it_IT"))
            if candidate == normalized { return wheel }
            if wheel.shortCode.lowercased() == normalized { return wheel }
        }
        // Alias frequenti nei dataset pubblici.
        switch normalized {
        case "rn", "ruota nazionale", "naz": return .nazionale
        case "ro": return .roma
        case "to", "torino ": return .torino
        default: return nil
        }
    }
}

/// Ambito di analisi: una ruota singola oppure tutte le ruote insieme.
enum WheelScope: Hashable, Identifiable, Sendable {
    case single(Wheel)
    case all

    var id: String {
        switch self {
        case .single(let wheel): return wheel.rawValue
        case .all: return "__all__"
        }
    }

    var displayName: String {
        switch self {
        case .single(let wheel): return wheel.displayName
        case .all: return "Tutte le ruote"
        }
    }

    static var allOptions: [WheelScope] {
        [.all] + Wheel.allCases.map { WheelScope.single($0) }
    }
}
