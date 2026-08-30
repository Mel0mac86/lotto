import Foundation
import Observation

@MainActor
@Observable
final class MonteCarloViewModel {

    var filter: AnalysisFilter
    var iterations: MonteCarloEngine.Iterations = .hundredThousand
    var result: MonteCarloResult?
    var isRunning = false
    var progress: Double = 0

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        self.filter = app.settings.defaultFilter()
    }

    func run() async {
        isRunning = true
        progress = 0
        defer { isRunning = false }

        let currentFilter = filter
        let weights = app.settings.weights
        let draws = app.draws(for: currentFilter.game)
        let iterationCount = iterations.rawValue

        result = await app.compute {
            let context = AnalysisContext(filter: currentFilter, allDraws: draws, weights: weights)
            return MonteCarloEngine.run(context: context, iterations: iterationCount)
        }
        progress = 1
    }

    /// Confronto frequenze simulate/storiche per i grafici.
    var frequencyComparison: [ComparisonPoint] {
        guard let result else { return [] }
        return (1...90).map { number in
            ComparisonPoint(key: number,
                            label: Theme.number(number),
                            simulated: (result.simulatedFrequency[number] ?? 0) * 100,
                            historical: (result.historicalFrequency[number] ?? 0) * 100)
        }
    }

    var sumComparison: [ComparisonPoint] {
        guard let result else { return [] }
        let simulatedTotal = Double(result.simulatedSums.values.reduce(0, +))
        let historicalTotal = Double(result.historicalSums.values.reduce(0, +))
        guard simulatedTotal > 0, historicalTotal > 0 else { return [] }

        var simulatedBuckets: [Int: Int] = [:]
        for (sum, count) in result.simulatedSums { simulatedBuckets[sum / 10 * 10, default: 0] += count }
        var historicalBuckets: [Int: Int] = [:]
        for (sum, count) in result.historicalSums { historicalBuckets[sum / 10 * 10, default: 0] += count }

        let keys = Set(simulatedBuckets.keys).union(historicalBuckets.keys).sorted()
        return keys.map { bucket in
            ComparisonPoint(key: bucket,
                            label: "\(bucket)",
                            simulated: Double(simulatedBuckets[bucket] ?? 0) / simulatedTotal * 100,
                            historical: Double(historicalBuckets[bucket] ?? 0) / historicalTotal * 100)
        }
    }

    var parityComparison: [ComparisonPoint] {
        guard let result else { return [] }
        let simulatedTotal = Double(result.simulatedEven.values.reduce(0, +))
        let historicalTotal = Double(result.historicalEven.values.reduce(0, +))
        guard simulatedTotal > 0, historicalTotal > 0 else { return [] }
        let keys = Set(result.simulatedEven.keys).union(result.historicalEven.keys).sorted()
        return keys.map { even in
            ComparisonPoint(key: even,
                            label: "\(even) pari",
                            simulated: Double(result.simulatedEven[even] ?? 0) / simulatedTotal * 100,
                            historical: Double(result.historicalEven[even] ?? 0) / historicalTotal * 100)
        }
    }

    var decadeComparison: [ComparisonPoint] {
        guard let result else { return [] }
        let simulatedTotal = Double(result.simulatedDecades.values.reduce(0, +))
        let historicalTotal = Double(result.historicalDecades.values.reduce(0, +))
        guard simulatedTotal > 0, historicalTotal > 0 else { return [] }
        return (0...8).map { decade in
            ComparisonPoint(key: decade,
                            label: "\(decade * 10 + 1)–\(decade * 10 + 10)",
                            simulated: Double(result.simulatedDecades[decade] ?? 0) / simulatedTotal * 100,
                            historical: Double(result.historicalDecades[decade] ?? 0) / historicalTotal * 100)
        }
    }
}

/// Punto di confronto fra distribuzione simulata e distribuzione storica.
struct ComparisonPoint: Identifiable, Sendable {
    let key: Int
    let label: String
    /// Percentuale sulla serie simulata.
    let simulated: Double
    /// Percentuale sulla serie storica.
    let historical: Double
    var id: Int { key }
    var difference: Double { historical - simulated }
}
