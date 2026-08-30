import Foundation

/// Contesto completo di un'analisi: estrazioni filtrate, statistiche, indici e score.
///
/// Viene costruito una sola volta e riutilizzato da tutti i generatori, così che
/// ambi, terni e cinquine siano coerenti tra loro.
struct AnalysisContext: Sendable {
    let filter: AnalysisFilter
    let draws: [DrawRecord]
    let statistics: DatasetStatistics
    let occurrences: SetOccurrenceIndex
    let scores: [Int: NumberScore]
    let weights: ScoringWeights

    var game: GameType { filter.game }
    var drawCount: Int { draws.count }
    var isEmpty: Bool { draws.isEmpty }

    /// Media e deviazione standard delle somme storiche, usate per il criterio di equilibrio.
    let sumMean: Double
    let sumStandardDeviation: Double

    init(filter: AnalysisFilter, allDraws: [DrawRecord], weights: ScoringWeights) {
        let filtered = StatisticsEngine.apply(filter, to: allDraws)
        self.filter = filter
        self.draws = filtered
        self.statistics = StatisticsEngine.computeStatistics(for: filtered, game: filter.game)
        self.occurrences = SetOccurrenceIndex(draws: filtered, drawnPerDraw: filter.game.drawnCount)
        self.weights = weights
        self.scores = ScoringEngine.score(statistics: statistics, weights: weights, range: filter.game.numberRange)

        let sums = statistics.sums.map(Double.init)
        if sums.isEmpty {
            // Valori teorici: media di k numeri uniformi su 1–90.
            let k = Double(filter.game.drawnCount)
            self.sumMean = k * 45.5
            self.sumStandardDeviation = (k * (90.0 * 90.0 - 1) / 12 * (90 - k) / 89).squareRoot()
        } else {
            let mean = sums.reduce(0, +) / Double(sums.count)
            let variance = sums.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(max(sums.count - 1, 1))
            self.sumMean = mean
            self.sumStandardDeviation = max(variance.squareRoot(), 1)
        }
    }

    func score(of number: Int) -> Double { scores[number]?.score ?? 0 }
    func stats(of number: Int) -> NumberStatistics { statistics.numbers[number] ?? NumberStatistics(number: number) }

    var rankedNumbers: [NumberScore] { ScoringEngine.ranked(scores) }

    /// I `limit` numeri con indice statistico più alto.
    func topNumbers(_ limit: Int) -> [Int] {
        Array(rankedNumbers.prefix(limit).map(\.number))
    }
}
