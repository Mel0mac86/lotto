import Foundation

/// Vettore di feature associato a un numero.
struct NumberFeatureVector: Sendable {
    let number: Int
    /// Feature normalizzate 0–1: frequenza, ritardo, trend, volatilità, co-occorrenza, recenza.
    let vector: [Double]

    static let featureNames = ["Frequenza", "Ritardo", "Trend", "Volatilità", "Co-occorrenza", "Recenza"]
}

/// Costruisce le matrici di feature usate dai modelli di machine learning.
///
/// - Important: le feature descrivono **il passato**. I modelli che le usano
///   servono a classificare e raggruppare pattern storici, non a prevedere
///   l'esito di un'estrazione casuale.
enum MLFeatureBuilder {

    static func numberFeatures(context: AnalysisContext) -> [NumberFeatureVector] {
        let items = (context.game.numberRange).compactMap { context.statistics.numbers[$0] }
        guard !items.isEmpty else { return [] }

        let frequencies = items.map { Double($0.occurrences) }
        let delays = items.map { Double($0.currentDelay) }
        let trends = items.map { ScoringEngine.trendScore($0.trendRatio) / 100 }
        let volatilities = items.map(\.volatility)
        let coOccurrences = items.map(\.coOccurrenceStrength)
        let recency = items.map { 1 - min(Double($0.currentDelay) / Double(max($0.maxDelay, 1)), 1) }

        let normalizedFrequency = normalize(frequencies)
        let normalizedDelay = normalize(delays)
        let normalizedVolatility = normalize(volatilities)
        let normalizedCoOccurrence = normalize(coOccurrences)

        return items.enumerated().map { index, item in
            NumberFeatureVector(number: item.number,
                                vector: [normalizedFrequency[index],
                                         normalizedDelay[index],
                                         trends[index],
                                         normalizedVolatility[index],
                                         normalizedCoOccurrence[index],
                                         recency[index]])
        }
    }

    /// Dataset supervisionato walk-forward: per ogni estrazione e per ogni numero,
    /// le feature calcolate **solo** sulle estrazioni precedenti e l'etichetta
    /// "il numero è uscito in questa estrazione".
    ///
    /// Serve esclusivamente a misurare quanto (poco) le feature storiche siano
    /// informative: è lo strumento con cui l'app dimostra l'assenza di potere predittivo.
    static func supervisedDataset(draws: [DrawRecord],
                                  game: GameType,
                                  warmup: Int = 200,
                                  stride: Int = 5) -> (features: [[Double]], labels: [Int]) {
        guard draws.count > warmup + 10 else { return ([], []) }
        var features: [[Double]] = []
        var labels: [Int] = []
        var index = warmup

        while index < draws.count {
            let history = Array(draws[0..<index])
            let statistics = StatisticsEngine.computeStatistics(for: history, game: game)
            let target = Set(draws[index].numbers)
            for number in game.numberRange {
                guard let item = statistics.numbers[number] else { continue }
                features.append([
                    item.frequency * 90,
                    Double(item.currentDelay) / 100,
                    ScoringEngine.trendScore(item.trendRatio) / 100,
                    item.volatility,
                    item.coOccurrenceStrength,
                    Double(item.maxDelay) / 100
                ])
                labels.append(target.contains(number) ? 1 : 0)
            }
            index += stride
        }
        return (features, labels)
    }

    static func normalize(_ values: [Double]) -> [Double] {
        guard let minimum = values.min(), let maximum = values.max(), maximum > minimum else {
            return values.map { _ in 0.5 }
        }
        return values.map { ($0 - minimum) / (maximum - minimum) }
    }
}
