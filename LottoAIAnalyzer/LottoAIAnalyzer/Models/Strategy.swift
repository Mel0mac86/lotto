import Foundation

/// Strategie di generazione delle combinazioni.
enum GenerationStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
    case frequency
    case delay
    case balanced
    case multiWheel
    case hot
    case cold
    case trend
    case statisticalRandom
    case conservative
    case diversified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frequency: return "Frequenza"
        case .delay: return "Ritardo"
        case .balanced: return "Bilanciata"
        case .multiWheel: return "Multi-ruota"
        case .hot: return "Hot"
        case .cold: return "Cold"
        case .trend: return "Trend"
        case .statisticalRandom: return "Random statistica"
        case .conservative: return "Conservativa"
        case .diversified: return "Diversificata"
        }
    }

    var explanation: String {
        switch self {
        case .frequency:
            return "Privilegia i numeri con la frequenza storica più alta nel periodo selezionato."
        case .delay:
            return "Privilegia i numeri con il ritardo attuale più elevato rispetto alla loro media storica."
        case .balanced:
            return "Mescola numeri frequenti, ritardatari e di frequenza media rispettando i vincoli di equilibrio."
        case .multiWheel:
            return "Considera i numeri che mostrano segnali statistici coerenti su più ruote contemporaneamente."
        case .hot:
            return "Solo numeri con frequenza recente superiore alla media del periodo."
        case .cold:
            return "Solo numeri con frequenza recente inferiore alla media del periodo."
        case .trend:
            return "Privilegia i numeri la cui frequenza recente è in crescita rispetto alla frequenza storica."
        case .statisticalRandom:
            return "Estrazione casuale vincolata: casuale, ma con somma, parità e distribuzione entro gli intervalli storici tipici."
        case .conservative:
            return "Solo numeri con indice statistico elevato, poca varianza."
        case .diversified:
            return "Massimizza la distanza dalle combinazioni già generate in questa sessione."
        }
    }

    /// Pesi di scoring associati alla strategia.
    var weights: ScoringWeights {
        switch self {
        case .frequency, .hot: return .frequencyFocused
        case .delay, .cold: return .delayFocused
        case .trend: return .trendFocused
        case .conservative: return ScoringWeights(frequency: 0.40, recency: 0.10, delay: 0.10,
                                                  trend: 0.10, coOccurrence: 0.10, stability: 0.20)
        default: return .balanced
        }
    }
}

/// Modalità di generazione della cinquina.
enum QuintupleMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case conservative
    case balanced
    case diversified
    case statisticalRandom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conservative: return "Conservativa"
        case .balanced: return "Bilanciata"
        case .diversified: return "Diversificata"
        case .statisticalRandom: return "Random statistica"
        }
    }

    var subtitle: String {
        switch self {
        case .conservative: return "Numeri con indice statistico elevato"
        case .balanced: return "Mix di frequenti, ritardatari e medi"
        case .diversified: return "Riduce la sovrapposizione con le combinazioni precedenti"
        case .statisticalRandom: return "Casuale entro vincoli statistici"
        }
    }

    var strategy: GenerationStrategy {
        switch self {
        case .conservative: return .conservative
        case .balanced: return .balanced
        case .diversified: return .diversified
        case .statisticalRandom: return .statisticalRandom
        }
    }
}

/// Filtri combinati della sezione "Analisi calda/fredda".
enum TemperatureFilter: String, CaseIterable, Identifiable, Sendable {
    case hot
    case cold
    case overdue
    case hotOverdue
    case coldOverdue
    case hotRecent
    case balanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hot: return "Hot"
        case .cold: return "Cold"
        case .overdue: return "Overdue"
        case .hotOverdue: return "Hot + Overdue"
        case .coldOverdue: return "Cold + Overdue"
        case .hotRecent: return "Hot + Recent"
        case .balanced: return "Balanced"
        }
    }

    var description: String {
        switch self {
        case .hot: return "Frequenza recente elevata nel periodo selezionato."
        case .cold: return "Frequenza recente bassa nel periodo selezionato."
        case .overdue: return "Ritardo attuale elevato rispetto al ritardo medio storico."
        case .hotOverdue: return "Frequenza recente elevata ma ritardo attuale sopra la media."
        case .coldOverdue: return "Frequenza recente bassa e ritardo attuale elevato."
        case .hotRecent: return "Frequenza recente elevata e ultima uscita ravvicinata."
        case .balanced: return "Valori intermedi su tutti gli indicatori."
        }
    }
}
