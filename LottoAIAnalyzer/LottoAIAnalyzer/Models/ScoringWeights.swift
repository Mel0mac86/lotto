import Foundation

/// Pesi configurabili dell'algoritmo **Statistical Number Score**.
///
/// Lo score risultante è un *indice statistico* descrittivo del passato,
/// non una probabilità di uscita.
struct ScoringWeights: Codable, Hashable, Sendable {
    var frequency: Double
    var recency: Double
    var delay: Double
    var trend: Double
    var coOccurrence: Double
    var stability: Double

    static let balanced = ScoringWeights(frequency: 0.30, recency: 0.15, delay: 0.20,
                                         trend: 0.15, coOccurrence: 0.10, stability: 0.10)

    static let frequencyFocused = ScoringWeights(frequency: 0.60, recency: 0.10, delay: 0.05,
                                                 trend: 0.10, coOccurrence: 0.10, stability: 0.05)

    static let delayFocused = ScoringWeights(frequency: 0.10, recency: 0.05, delay: 0.60,
                                             trend: 0.05, coOccurrence: 0.10, stability: 0.10)

    static let trendFocused = ScoringWeights(frequency: 0.15, recency: 0.25, delay: 0.05,
                                             trend: 0.45, coOccurrence: 0.05, stability: 0.05)

    var total: Double { frequency + recency + delay + trend + coOccurrence + stability }

    /// Riporta la somma dei pesi a 1 così che lo score resti nell'intervallo 0–100.
    func normalized() -> ScoringWeights {
        let sum = total
        guard sum > 0 else { return .balanced }
        return ScoringWeights(frequency: frequency / sum,
                              recency: recency / sum,
                              delay: delay / sum,
                              trend: trend / sum,
                              coOccurrence: coOccurrence / sum,
                              stability: stability / sum)
    }
}

/// Fascia qualitativa dello score (solo descrittiva).
enum ScoreBand: String, Sendable {
    case high
    case medium
    case low

    init(score: Double) {
        switch score {
        case 80...: self = .high
        case 50..<80: self = .medium
        default: self = .low
        }
    }

    var label: String {
        switch self {
        case .high: return "Indice statistico alto"
        case .medium: return "Indice statistico medio"
        case .low: return "Indice statistico basso"
        }
    }

    var emoji: String {
        switch self {
        case .high: return "🟢"
        case .medium: return "🟡"
        case .low: return "🔴"
        }
    }
}
