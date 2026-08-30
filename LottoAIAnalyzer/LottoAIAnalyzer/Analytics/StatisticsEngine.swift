import Foundation

/// Motore statistico di base: dalle estrazioni grezze alle metriche per numero.
///
/// È volutamente privo di stato e indipendente da SwiftData/SwiftUI, così da poter
/// essere eseguito fuori dal main actor e riutilizzato dai backtest.
enum StatisticsEngine {

    // MARK: - Filtro

    /// Applica il filtro a un insieme di estrazioni già ordinate per data crescente.
    ///
    /// - Important: `cutoffDate` è un limite **stretto**: le estrazioni con data
    ///   maggiore o uguale al cutoff vengono eliminate. È questa la barriera che
    ///   impedisce il data leakage nei backtest walk-forward.
    static func apply(_ filter: AnalysisFilter, to draws: [DrawRecord]) -> [DrawRecord] {
        var result = draws.filter { $0.game == filter.game }

        if filter.game.usesWheels, case .single(let wheel) = filter.wheelScope {
            result = result.filter { $0.wheel == wheel }
        }

        if let cutoff = filter.cutoffDate {
            result = result.filter { $0.date < cutoff }
        }

        if let year = filter.calendarYear {
            result = result.filter { $0.year == year }
        } else {
            let reference = filter.cutoffDate ?? result.last?.date ?? Date()
            if let start = filter.period.startDate(relativeTo: reference) {
                result = result.filter { $0.date >= start }
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    // MARK: - Calcolo

    /// Calcola tutte le statistiche descrittive per l'insieme di estrazioni fornito.
    static func computeStatistics(for draws: [DrawRecord], game: GameType) -> DatasetStatistics {
        var stats = DatasetStatistics()
        stats.drawCount = draws.count
        stats.firstDate = draws.first?.date
        stats.lastDate = draws.last?.date
        guard !draws.isEmpty else {
            stats.numbers = Dictionary(uniqueKeysWithValues: game.numberRange.map { ($0, NumberStatistics(number: $0)) })
            return stats
        }

        let range = game.numberRange
        let drawn = game.drawnCount
        let total = draws.count

        var occurrences = [Int: Int](minimumCapacity: 90)
        var lastIndex = [Int: Int](minimumCapacity: 90)
        var lastDate = [Int: Date](minimumCapacity: 90)
        var gaps = [Int: [Int]](minimumCapacity: 90)
        var firstIndex = [Int: Int](minimumCapacity: 90)

        for number in range {
            occurrences[number] = 0
            gaps[number] = []
        }

        for (index, draw) in draws.enumerated() {
            stats.sums.append(draw.sum)
            stats.evenDistribution[draw.evenCount, default: 0] += 1
            stats.lowDistribution[draw.lowCount, default: 0] += 1
            if draw.consecutivePairsCount > 0 { stats.drawsWithConsecutives += 1 }

            let year = draw.year
            let month = draw.month

            for number in draw.numbers {
                occurrences[number, default: 0] += 1
                stats.decadeDistribution[min((number - 1) / 10, 8), default: 0] += 1
                stats.unitDistribution[number % 10, default: 0] += 1
                stats.byYear[year, default: [:]][number, default: 0] += 1
                stats.byMonth[month, default: [:]][number, default: 0] += 1
                if let wheel = draw.wheel {
                    stats.byWheel[wheel, default: [:]][number, default: 0] += 1
                }

                if let previous = lastIndex[number] {
                    gaps[number, default: []].append(index - previous - 1)
                } else {
                    firstIndex[number] = index
                    // Ritardo iniziale: estrazioni trascorse prima della prima uscita.
                    gaps[number, default: []].append(index)
                }
                lastIndex[number] = index
                lastDate[number] = draw.date
            }
        }

        // Finestra "recente": ultimo quarto delle estrazioni (minimo 20, se disponibili).
        let recentWindow = max(min(total, 20), total / 4)
        let recentDraws = Array(draws.suffix(recentWindow))
        var recentOccurrences = [Int: Int](minimumCapacity: 90)
        for draw in recentDraws {
            for number in draw.numbers { recentOccurrences[number, default: 0] += 1 }
        }

        // Volatilità: frequenze su massimo 8 sotto-periodi di uguale ampiezza.
        let bucketCount = min(8, max(2, total / 25))
        let bucketSize = max(1, total / bucketCount)
        var bucketOccurrences: [Int: [Int]] = [:]
        for number in range { bucketOccurrences[number] = Array(repeating: 0, count: bucketCount) }
        for (index, draw) in draws.enumerated() {
            let bucket = min(index / bucketSize, bucketCount - 1)
            for number in draw.numbers { bucketOccurrences[number]?[bucket] += 1 }
        }

        let matrix = CoOccurrenceMatrix.build(from: draws, drawnPerDraw: drawn)
        let expectedFrequency = Double(drawn) / Double(range.count)

        for number in range {
            var item = NumberStatistics(number: number)
            let count = occurrences[number] ?? 0
            item.occurrences = count
            item.frequency = Double(count) / Double(total)
            item.expectedFrequency = expectedFrequency
            item.frequencyRatio = expectedFrequency > 0 ? item.frequency / expectedFrequency : 0

            if let last = lastIndex[number] {
                item.currentDelay = total - 1 - last
                item.lastSeenIndex = last
                item.lastSeen = lastDate[number]
            } else {
                // Mai uscito nel periodo: il ritardo è pari all'intera finestra.
                item.currentDelay = total
            }

            var allGaps = gaps[number] ?? []
            allGaps.append(item.currentDelay)
            item.averageDelay = allGaps.isEmpty ? 0 : Double(allGaps.reduce(0, +)) / Double(allGaps.count)
            item.maxDelay = allGaps.max() ?? 0
            item.delayRatio = item.maxDelay > 0 ? Double(item.currentDelay) / Double(item.maxDelay) : 0

            let recentCount = recentOccurrences[number] ?? 0
            item.recentFrequency = recentDraws.isEmpty ? 0 : Double(recentCount) / Double(recentDraws.count)
            item.trendRatio = item.frequency > 0 ? item.recentFrequency / item.frequency : (item.recentFrequency > 0 ? 2 : 1)

            if let buckets = bucketOccurrences[number], buckets.count > 1 {
                let mean = Double(buckets.reduce(0, +)) / Double(buckets.count)
                if mean > 0 {
                    let variance = buckets.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(buckets.count)
                    item.volatility = variance.squareRoot() / mean
                } else {
                    item.volatility = 1
                }
            }

            item.coOccurrenceStrength = matrix.strength(of: number)
            stats.numbers[number] = item
        }

        // Percentili di frequenza.
        let ordered = stats.numbers.values.sorted { $0.occurrences < $1.occurrences }
        let denominator = Double(max(ordered.count - 1, 1))
        for (rank, item) in ordered.enumerated() {
            stats.numbers[item.number]?.frequencyPercentile = Double(rank) / denominator * 100
        }

        return stats
    }

    /// Statistiche complete (filtro + calcolo) in un solo passaggio.
    static func statistics(for filter: AnalysisFilter, in draws: [DrawRecord]) -> DatasetStatistics {
        let filtered = apply(filter, to: draws)
        return computeStatistics(for: filtered, game: filter.game)
    }

    /// Suddivide le estrazioni per ruota (usato dalle analisi multi-ruota).
    static func groupedByWheel(_ draws: [DrawRecord]) -> [Wheel: [DrawRecord]] {
        var grouped: [Wheel: [DrawRecord]] = [:]
        for draw in draws {
            guard let wheel = draw.wheel else { continue }
            grouped[wheel, default: []].append(draw)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.date < $1.date }
        }
        return grouped
    }
}
