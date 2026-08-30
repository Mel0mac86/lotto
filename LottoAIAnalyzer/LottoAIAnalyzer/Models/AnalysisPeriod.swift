import Foundation

/// Finestra temporale su cui vengono calcolate le statistiche.
enum AnalysisPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneYear
    case twoYears
    case threeYears
    case fiveYears
    case tenYears
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneYear: return "Ultimo anno"
        case .twoYears: return "Ultimi 2 anni"
        case .threeYears: return "Ultimi 3 anni"
        case .fiveYears: return "Ultimi 5 anni"
        case .tenYears: return "Ultimi 10 anni"
        case .all: return "Tutta la storia"
        }
    }

    var years: Int? {
        switch self {
        case .oneYear: return 1
        case .twoYears: return 2
        case .threeYears: return 3
        case .fiveYears: return 5
        case .tenYears: return 10
        case .all: return nil
        }
    }

    /// Data di inizio del periodo rispetto a un riferimento (di norma "oggi"
    /// oppure, durante un backtest, la data dell'estrazione simulata).
    func startDate(relativeTo reference: Date) -> Date? {
        guard let years else { return nil }
        return Calendar.italian.date(byAdding: .year, value: -years, to: reference)
    }
}

/// Filtro completo che identifica un sottoinsieme di estrazioni.
struct AnalysisFilter: Hashable, Sendable {
    var game: GameType
    var wheelScope: WheelScope
    var period: AnalysisPeriod
    /// Se valorizzato, limita l'analisi a un singolo anno solare (sezione "Analisi annuale").
    var calendarYear: Int?
    /// Limite superiore stretto: nessuna estrazione con data >= questo valore viene usata.
    /// È il meccanismo che rende impossibile il data leakage nei backtest.
    var cutoffDate: Date?

    init(game: GameType = .lotto,
         wheelScope: WheelScope = .single(.bari),
         period: AnalysisPeriod = .fiveYears,
         calendarYear: Int? = nil,
         cutoffDate: Date? = nil) {
        self.game = game
        self.wheelScope = wheelScope
        self.period = period
        self.calendarYear = calendarYear
        self.cutoffDate = cutoffDate
    }

    var describesAllWheels: Bool {
        if case .all = wheelScope { return true }
        return false
    }

    var summary: String {
        var parts: [String] = [game.displayName]
        if game.usesWheels { parts.append(wheelScope.displayName) }
        if let calendarYear {
            parts.append("anno \(calendarYear)")
        } else {
            parts.append(period.displayName.lowercased())
        }
        return parts.joined(separator: " · ")
    }
}
