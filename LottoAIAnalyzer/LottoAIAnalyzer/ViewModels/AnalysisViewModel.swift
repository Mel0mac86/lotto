import Foundation
import Observation

/// Riga della tabella "Analisi annuale".
struct YearlyRow: Identifiable, Sendable {
    let number: Int
    let occurrences: Int
    let frequency: Double
    let delay: Int
    let percentile: Double
    var id: Int { number }
}

/// Confronto della frequenza di un numero fra più anni.
struct YearComparisonRow: Identifiable, Sendable {
    let number: Int
    /// [anno: uscite]
    let byYear: [Int: Int]
    /// Scarto standardizzato fra l'anno più recente e la media degli altri.
    let deviation: Double
    var id: Int { number }
}

@MainActor
@Observable
final class AnalysisViewModel {

    var filter: AnalysisFilter
    var context: AnalysisContext?
    var isLoading = false

    /// Anni selezionati per il confronto.
    var comparisonYears: [Int] = []

    private let app: AppModel

    init(app: AppModel, filter: AnalysisFilter? = nil) {
        self.app = app
        self.filter = filter ?? app.settings.defaultFilter()
    }

    // MARK: - Caricamento

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let currentFilter = filter
        let weights = app.settings.weights
        let draws = app.draws(for: currentFilter.game)
        context = await app.compute {
            AnalysisContext(filter: currentFilter, allDraws: draws, weights: weights)
        }
    }

    func update(filter newFilter: AnalysisFilter) async {
        filter = newFilter
        await load()
    }

    // MARK: - Tabelle

    var yearlyRows: [YearlyRow] {
        guard let context else { return [] }
        return context.game.numberRange.compactMap { number in
            guard let stats = context.statistics.numbers[number] else { return nil }
            return YearlyRow(number: number,
                             occurrences: stats.occurrences,
                             frequency: stats.frequency,
                             delay: stats.currentDelay,
                             percentile: stats.frequencyPercentile)
        }
    }

    var rankedNumbers: [NumberScore] { context?.rankedNumbers ?? [] }

    var overdueNumbers: [NumberStatistics] {
        guard let context else { return [] }
        return HotColdEngine.overdueRanking(context: context, limit: 90)
    }

    func temperatureEntries(_ temperature: TemperatureFilter, limit: Int = 20) -> [TemperatureEntry] {
        guard let context else { return [] }
        return HotColdEngine.entries(context: context, filter: temperature, limit: limit)
    }

    // MARK: - Confronto fra anni

    var availableYears: [Int] { app.availableYears(for: filter.game) }

    func comparison(years: [Int]) async -> [YearComparisonRow] {
        let game = filter.game
        let scope = filter.wheelScope
        let draws = app.draws(for: game)
        let weights = app.settings.weights

        return await app.compute {
            var counts: [Int: [Int: Int]] = [:]  // [numero: [anno: uscite]]
            for year in years {
                let yearFilter = AnalysisFilter(game: game, wheelScope: scope, period: .all, calendarYear: year)
                let context = AnalysisContext(filter: yearFilter, allDraws: draws, weights: weights)
                for number in game.numberRange {
                    counts[number, default: [:]][year] = context.stats(of: number).occurrences
                }
            }
            guard let mostRecent = years.max() else { return [] }

            return counts.map { number, byYear -> YearComparisonRow in
                let others = byYear.filter { $0.key != mostRecent }.map { Double($0.value) }
                let recent = Double(byYear[mostRecent] ?? 0)
                guard !others.isEmpty else {
                    return YearComparisonRow(number: number, byYear: byYear, deviation: 0)
                }
                let mean = others.reduce(0, +) / Double(others.count)
                let variance = others.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(others.count)
                let sigma = max(variance.squareRoot(), 1)
                return YearComparisonRow(number: number, byYear: byYear, deviation: (recent - mean) / sigma)
            }
            .sorted { abs($0.deviation) > abs($1.deviation) }
        }
    }

    // MARK: - Grafici

    /// Serie [anno: uscite] per un numero.
    func yearlySeries(for number: Int) -> [YearPoint] {
        guard let context else { return [] }
        return context.statistics.byYear
            .map { YearPoint(year: $0.key, count: $0.value[number] ?? 0) }
            .sorted { $0.year < $1.year }
    }

    /// Serie [mese: uscite] per un numero.
    func monthlySeries(for number: Int) -> [MonthPoint] {
        guard let context else { return [] }
        return (1...12).map { month in
            MonthPoint(month: month, count: context.statistics.byMonth[month]?[number] ?? 0)
        }
    }

    /// Heatmap numeri × anni, con valori normalizzati 0–1 all'interno di ogni anno.
    func heatmapNumbersByYear() -> [YearHeatCell] {
        guard let context else { return [] }
        var cells: [YearHeatCell] = []
        for (year, counts) in context.statistics.byYear {
            let maximum = Double(counts.values.max() ?? 1)
            for number in context.game.numberRange {
                cells.append(YearHeatCell(year: year,
                                          number: number,
                                          value: Double(counts[number] ?? 0) / max(maximum, 1)))
            }
        }
        return cells.sorted { $0.year == $1.year ? $0.number < $1.number : $0.year < $1.year }
    }

    /// Heatmap ruote × numeri (solo Lotto, ambito "tutte le ruote").
    func heatmapWheelsByNumber() -> [WheelHeatCell] {
        guard let context else { return [] }
        var cells: [WheelHeatCell] = []
        for (wheel, counts) in context.statistics.byWheel {
            let maximum = Double(counts.values.max() ?? 1)
            for number in 1...90 {
                cells.append(WheelHeatCell(wheel: wheel,
                                           number: number,
                                           value: Double(counts[number] ?? 0) / max(maximum, 1)))
            }
        }
        return cells.sorted { $0.wheel.rawValue == $1.wheel.rawValue ? $0.number < $1.number : $0.wheel.rawValue < $1.wheel.rawValue }
    }

    var sumDistribution: [SumBucket] {
        guard let context else { return [] }
        let grouped = Dictionary(grouping: context.statistics.sums) { $0 / 10 * 10 }
        return grouped.map { SumBucket(sum: $0.key, count: $0.value.count) }.sorted { $0.sum < $1.sum }
    }

    var parityDistribution: [CountBucket] {
        guard let context else { return [] }
        return context.statistics.evenDistribution
            .map { CountBucket(key: $0.key, count: $0.value) }
            .sorted { $0.key < $1.key }
    }

    var decadeDistribution: [CountBucket] {
        guard let context else { return [] }
        return (0...8).map { CountBucket(key: $0, count: context.statistics.decadeDistribution[$0] ?? 0) }
    }

    var unitDistribution: [CountBucket] {
        guard let context else { return [] }
        return (0...9).map { CountBucket(key: $0, count: context.statistics.unitDistribution[$0] ?? 0) }
    }
}

// MARK: - Punti dati per i grafici
//
// Swift Charts richiede elementi identificabili: le tuple non espongono key path,
// quindi ogni serie ha il proprio tipo.

struct YearPoint: Identifiable, Sendable {
    let year: Int
    let count: Int
    var id: Int { year }
}

struct MonthPoint: Identifiable, Sendable {
    let month: Int
    let count: Int
    var id: Int { month }
    var label: String {
        let symbols = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
        return symbols[max(min(month - 1, 11), 0)]
    }
}

struct YearHeatCell: Identifiable, Sendable {
    let year: Int
    let number: Int
    let value: Double
    var id: String { "\(year)-\(number)" }
}

struct WheelHeatCell: Identifiable, Sendable {
    let wheel: Wheel
    let number: Int
    let value: Double
    var id: String { "\(wheel.rawValue)-\(number)" }
}

struct SumBucket: Identifiable, Sendable {
    let sum: Int
    let count: Int
    var id: Int { sum }
    var label: String { "\(sum)–\(sum + 9)" }
}

/// Bucket generico usato per parità, decine e unità.
struct CountBucket: Identifiable, Sendable {
    let key: Int
    let count: Int
    var id: Int { key }
    var decadeLabel: String { "\(key * 10 + 1)–\(key * 10 + 10)" }
}
