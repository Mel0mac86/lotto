import Foundation

/// Classificazione calda/fredda/ritardataria di un numero.
struct TemperatureEntry: Identifiable, Sendable {
    let number: Int
    let statistics: NumberStatistics
    let score: Double
    let tags: [String]

    var id: Int { number }
    var band: ScoreBand { ScoreBand(score: score) }
}

/// **ANALISI CALDA/FREDDA** — hot, cold, overdue e le loro combinazioni.
enum HotColdEngine {

    static func entries(context: AnalysisContext, filter: TemperatureFilter, limit: Int = 20) -> [TemperatureEntry] {
        let items = context.game.numberRange.compactMap { context.statistics.numbers[$0] }
        guard !items.isEmpty else { return [] }

        let matching = items.filter { matches($0, filter: filter) }
        let source = matching.isEmpty ? items : matching

        return source.map { item -> TemperatureEntry in
            TemperatureEntry(number: item.number,
                             statistics: item,
                             score: context.score(of: item.number),
                             tags: tags(for: item))
        }
        .sorted { lhs, rhs in
            switch filter {
            case .hot, .hotRecent:
                return lhs.statistics.trendRatio > rhs.statistics.trendRatio
            case .cold:
                return lhs.statistics.trendRatio < rhs.statistics.trendRatio
            case .overdue, .hotOverdue, .coldOverdue:
                return lhs.statistics.currentDelay > rhs.statistics.currentDelay
            case .balanced:
                return lhs.score > rhs.score
            }
        }
        .prefix(limit)
        .map { $0 }
    }

    static func matches(_ item: NumberStatistics, filter: TemperatureFilter) -> Bool {
        switch filter {
        case .hot: return item.isHot
        case .cold: return item.isCold
        case .overdue: return item.isOverdue
        case .hotOverdue: return item.isHot && item.isOverdue
        case .coldOverdue: return item.isCold && item.isOverdue
        case .hotRecent: return item.isHot && item.currentDelay <= max(Int(item.averageDelay / 2), 3)
        case .balanced:
            return !item.isHot && !item.isCold && !item.isOverdue
        }
    }

    static func tags(for item: NumberStatistics) -> [String] {
        var result: [String] = []
        if item.isHot { result.append("🔥 Hot") }
        if item.isCold { result.append("❄️ Cold") }
        if item.isOverdue { result.append("⏳ Overdue") }
        if result.isEmpty { result.append("⚖️ Equilibrato") }
        return result
    }

    /// Numeri ritardatari ordinati per ritardo attuale.
    static func overdueRanking(context: AnalysisContext, limit: Int = 30) -> [NumberStatistics] {
        let items = context.game.numberRange.compactMap { context.statistics.numbers[$0] }
        return Array(items.sorted { $0.currentDelay > $1.currentDelay }.prefix(limit))
    }
}
