import Foundation

/// Risultato dell'analisi di un ambo.
struct PairResult: Hashable, Identifiable, Sendable {
    let first: Int
    let second: Int
    var score: Double
    var components: ScoreComponents
    /// Uscite congiunte nel periodo analizzato.
    var jointCount: Int
    /// Uscite congiunte attese in caso di pura casualità.
    var expectedCount: Double
    /// Estrazioni trascorse dall'ultima uscita congiunta.
    var delay: Int
    /// Uscite congiunte nell'ultimo quarto del periodo.
    var recentCount: Int
    var reasons: [String] = []

    var id: String { "\(first)-\(second)" }
    var numbers: [Int] { [first, second] }
    var formatted: String { String(format: "%02d – %02d", first, second) }
    var band: ScoreBand { ScoreBand(score: score) }
    var lift: Double { expectedCount > 0 ? Double(jointCount) / expectedCount : 0 }
}

/// **GENERA AMBO** — valuta tutte le 4.005 coppie possibili fra 1 e 90.
enum PairGenerator {

    static func topPairs(context: AnalysisContext,
                         limit: Int = 10,
                         restrictedTo pool: Set<Int>? = nil) -> [PairResult] {
        guard !context.isEmpty else { return [] }
        let range = context.game.numberRange
        let recentWindow = max(min(context.drawCount, 20), context.drawCount / 4)
        let recentDraws = Array(context.draws.suffix(recentWindow))
        var recentPairCounts = [Int: Int]()
        for draw in recentDraws {
            let numbers = draw.numbers
            guard numbers.count >= 2 else { continue }
            for i in 0..<(numbers.count - 1) {
                for j in (i + 1)..<numbers.count {
                    recentPairCounts[CoOccurrenceMatrix.index(numbers[i], numbers[j]), default: 0] += 1
                }
            }
        }

        var results: [PairResult] = []
        results.reserveCapacity(CoOccurrenceMatrix.pairCount)
        let expected = context.occurrences.expectedPairCount

        for a in range.lowerBound..<range.upperBound {
            if let pool, !pool.contains(a) { continue }
            for b in (a + 1)...range.upperBound {
                if let pool, !pool.contains(b) { continue }
                let evaluation = CombinationEngine.rawScore([a, b], context: context, weights: .pair)
                results.append(PairResult(first: a,
                                          second: b,
                                          score: evaluation.score,
                                          components: evaluation.components,
                                          jointCount: context.occurrences.pairCount(a, b),
                                          expectedCount: expected,
                                          delay: context.occurrences.pairDelay(a, b),
                                          recentCount: recentPairCounts[CoOccurrenceMatrix.index(a, b)] ?? 0))
            }
        }

        let top = results.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.jointCount > rhs.jointCount }
            return lhs.score > rhs.score
        }.prefix(limit)

        return top.map { pair in
            var enriched = pair
            enriched.reasons = reasons(for: pair, context: context)
            return enriched
        }
    }

    static func reasons(for pair: PairResult, context: AnalysisContext) -> [String] {
        var lines: [String] = []
        let first = context.stats(of: pair.first)
        let second = context.stats(of: pair.second)

        lines.append(String(format: "Uscite congiunte: %d su %d estrazioni (attese dal caso: %.1f).",
                            pair.jointCount, context.drawCount, pair.expectedCount))
        if pair.lift > 1.05 {
            lines.append(String(format: "Ricorrenza superiore all'atteso del %.0f%%.", (pair.lift - 1) * 100))
        } else if pair.lift < 0.95 && pair.expectedCount > 0 {
            lines.append(String(format: "Ricorrenza inferiore all'atteso del %.0f%%.", (1 - pair.lift) * 100))
        } else {
            lines.append("Ricorrenza congiunta sostanzialmente in linea con l'atteso casuale.")
        }
        lines.append(String(format: "Ritardo dell'ambo: %d estrazioni dall'ultima uscita congiunta.", pair.delay))
        lines.append(String(format: "Frequenze individuali: %02d con %d uscite (ritardo %d), %02d con %d uscite (ritardo %d).",
                            first.number, first.occurrences, first.currentDelay,
                            second.number, second.occurrences, second.currentDelay))
        if pair.recentCount > 0 {
            lines.append(String(format: "Nell'ultima parte del periodo la coppia è uscita %d volte.", pair.recentCount))
        }
        lines.append(Disclaimer.explainer)
        return lines
    }
}
