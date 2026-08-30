import Foundation

/// Risultato dello scoring di un singolo numero.
struct NumberScore: Hashable, Identifiable, Sendable {
    let number: Int
    /// Indice statistico complessivo 0–100.
    var score: Double
    var components: ScoreComponents
    var statistics: NumberStatistics

    var id: Int { number }
    var band: ScoreBand { ScoreBand(score: score) }
}

/// Implementa lo **STATISTICAL NUMBER SCORE**.
///
/// Ogni criterio viene normalizzato fra 0 e 100 rispetto agli altri 89 numeri
/// dello stesso insieme, poi combinato secondo i pesi configurati.
///
/// Il risultato è un *indice statistico* che descrive il comportamento passato
/// di un numero: non è, e non va presentato come, una probabilità di uscita.
enum ScoringEngine {

    static func score(statistics stats: DatasetStatistics,
                      weights rawWeights: ScoringWeights,
                      range: ClosedRange<Int> = 1...90) -> [Int: NumberScore] {
        let weights = rawWeights.normalized()
        let items = range.compactMap { stats.numbers[$0] }
        guard !items.isEmpty else { return [:] }

        let frequencyRank = percentileRanks(items.map { Double($0.occurrences) })
        let coOccurrenceRank = percentileRanks(items.map(\.coOccurrenceStrength))
        let delayValues = items.map { Double($0.currentDelay) }
        let delayRank = percentileRanks(delayValues)
        let volatilityRank = percentileRanks(items.map(\.volatility))

        var result: [Int: NumberScore] = [:]
        result.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            var components = ScoreComponents()
            components.frequency = frequencyRank[index]
            // Recenza: alto = uscito da poco. È l'inverso del ritardo.
            components.recency = 100 - delayRank[index]
            components.delay = delayRank[index]
            components.trend = trendScore(item.trendRatio)
            components.coOccurrence = coOccurrenceRank[index]
            // Stabilità: alto = frequenza costante nel tempo (bassa volatilità).
            components.stability = 100 - volatilityRank[index]

            let total = components.frequency * weights.frequency
                + components.recency * weights.recency
                + components.delay * weights.delay
                + components.trend * weights.trend
                + components.coOccurrence * weights.coOccurrence
                + components.stability * weights.stability

            result[item.number] = NumberScore(number: item.number,
                                              score: clamp(total),
                                              components: components,
                                              statistics: item)
        }
        return result
    }

    /// Mappa il rapporto frequenza recente / frequenza storica su 0–100.
    /// Un rapporto di 1.0 (nessun cambiamento) restituisce 50.
    static func trendScore(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return 50 }
        let logRatio = log(max(ratio, 0.01))
        // 4.0 comprime la curva: ±60% di variazione copre circa l'intero intervallo utile.
        let sigmoid = 1 / (1 + exp(-logRatio * 4.0))
        return clamp(sigmoid * 100)
    }

    /// Percentile 0–100 di ogni valore rispetto agli altri, con gestione dei pari merito.
    static func percentileRanks(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return values.map { _ in 50 } }
        let sorted = values.enumerated().sorted { $0.element < $1.element }
        var ranks = [Double](repeating: 0, count: values.count)
        let denominator = Double(values.count - 1)

        var position = 0
        while position < sorted.count {
            var end = position
            while end + 1 < sorted.count && sorted[end + 1].element == sorted[position].element { end += 1 }
            // Media dei ranghi per i valori uguali.
            let averageRank = Double(position + end) / 2
            let percentile = averageRank / denominator * 100
            for index in position...end { ranks[sorted[index].offset] = percentile }
            position = end + 1
        }
        return ranks
    }

    /// Normalizzazione min–max su 0–100.
    static func minMax(_ values: [Double]) -> [Double] {
        guard let minimum = values.min(), let maximum = values.max(), maximum > minimum else {
            return values.map { _ in 50 }
        }
        return values.map { ($0 - minimum) / (maximum - minimum) * 100 }
    }

    @inline(__always)
    static func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        guard value.isFinite else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }

    /// Ordina i numeri per indice statistico decrescente.
    static func ranked(_ scores: [Int: NumberScore]) -> [NumberScore] {
        scores.values.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.number < rhs.number }
            return lhs.score > rhs.score
        }
    }
}
