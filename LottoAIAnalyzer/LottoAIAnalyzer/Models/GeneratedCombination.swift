import Foundation
import SwiftData

/// Combinazione generata e salvata dall'utente (per confronti e report).
@Model
final class SavedCombination {
    /// Identificativo stabile della combinazione. Non si chiama `id` per non
    /// entrare in conflitto con l'`Identifiable` che SwiftData sintetizza.
    var combinationID: UUID
    var createdAt: Date
    var gameRaw: String
    var wheelRaw: String?
    var numbers: [Int]
    var score: Double
    var strategyRaw: String
    var periodRaw: String
    var rationale: String
    var isFavorite: Bool

    init(combination: ScoredCombination,
         game: GameType,
         wheel: Wheel?,
         strategy: GenerationStrategy,
         period: AnalysisPeriod) {
        self.combinationID = UUID()
        self.createdAt = Date()
        self.gameRaw = game.rawValue
        self.wheelRaw = wheel?.rawValue
        self.numbers = combination.numbers
        self.score = combination.score
        self.strategyRaw = strategy.rawValue
        self.periodRaw = period.rawValue
        self.rationale = combination.reasons.joined(separator: "\n")
        self.isFavorite = false
    }

    var game: GameType { GameType(rawValue: gameRaw) ?? .lotto }
    var wheel: Wheel? { wheelRaw.flatMap { Wheel(rawValue: $0) } }
    var strategy: GenerationStrategy { GenerationStrategy(rawValue: strategyRaw) ?? .balanced }
    var period: AnalysisPeriod { AnalysisPeriod(rawValue: periodRaw) ?? .fiveYears }
    var formattedNumbers: String { numbers.map { String(format: "%02d", $0) }.joined(separator: " – ") }
}

/// Una combinazione con il suo indice statistico e le motivazioni.
struct ScoredCombination: Hashable, Identifiable, Sendable {
    var numbers: [Int]
    /// Indice statistico 0–100.
    var score: Double
    /// Contributi normalizzati dei singoli criteri (0–100).
    var components: ScoreComponents
    /// Spiegazioni in italiano, mostrate nella sezione "Perché?".
    var reasons: [String]

    var id: String { numbers.map(String.init).joined(separator: "-") }

    var band: ScoreBand { ScoreBand(score: score) }

    var formatted: String { numbers.map { String(format: "%02d", $0) }.joined(separator: " – ") }

    var sum: Int { numbers.reduce(0, +) }
    var evenCount: Int { numbers.filter { $0 % 2 == 0 }.count }
    var oddCount: Int { numbers.count - evenCount }
    var lowCount: Int { numbers.filter { $0 <= 45 }.count }
    var highCount: Int { numbers.count - lowCount }

    var averageGap: Double {
        guard numbers.count > 1 else { return 0 }
        let sorted = numbers.sorted()
        var total = 0
        for index in 1..<sorted.count { total += sorted[index] - sorted[index - 1] }
        return Double(total) / Double(sorted.count - 1)
    }

    var decadeDistribution: [Int: Int] {
        Dictionary(grouping: numbers) { min(($0 - 1) / 10, 8) }.mapValues { $0.count }
    }
}

/// Scomposizione dell'indice statistico nei suoi criteri.
struct ScoreComponents: Hashable, Sendable {
    var frequency: Double = 0
    var recency: Double = 0
    var delay: Double = 0
    var trend: Double = 0
    var coOccurrence: Double = 0
    var stability: Double = 0
    var balance: Double = 0

    var labelledValues: [ScoreComponentValue] {
        [ScoreComponentValue(label: "Frequenza", value: frequency),
         ScoreComponentValue(label: "Recenza", value: recency),
         ScoreComponentValue(label: "Ritardo", value: delay),
         ScoreComponentValue(label: "Trend", value: trend),
         ScoreComponentValue(label: "Co-occorrenza", value: coOccurrence),
         ScoreComponentValue(label: "Stabilità", value: stability),
         ScoreComponentValue(label: "Equilibrio", value: balance)]
    }
}

/// Un criterio dell'indice statistico con il suo valore 0–100.
struct ScoreComponentValue: Hashable, Identifiable, Sendable {
    let label: String
    let value: Double
    var id: String { label }
}
