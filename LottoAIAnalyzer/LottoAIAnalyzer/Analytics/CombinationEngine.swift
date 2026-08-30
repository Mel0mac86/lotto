import Foundation

/// Costruisce e valuta combinazioni (ambi, terni, cinquine/sestine).
enum CombinationEngine {

    /// Pesi con cui i criteri concorrono all'indice statistico di una combinazione.
    struct CombinationWeights: Sendable {
        var numberScore: Double = 0.55
        var coOccurrence: Double = 0.25
        var balance: Double = 0.20

        static let `default` = CombinationWeights()
        /// Per gli ambi la co-occorrenza pesa di più: è il criterio caratterizzante.
        static let pair = CombinationWeights(numberScore: 0.45, coOccurrence: 0.45, balance: 0.10)
        static let triple = CombinationWeights(numberScore: 0.45, coOccurrence: 0.35, balance: 0.20)
    }

    // MARK: - Valutazione di una combinazione qualsiasi

    /// Calcola indice statistico e componenti **senza** generare le spiegazioni.
    /// È il percorso veloce usato quando si valutano migliaia di combinazioni.
    static func rawScore(_ numbers: [Int],
                         context: AnalysisContext,
                         weights: CombinationWeights = .default) -> (score: Double, components: ScoreComponents) {
        guard !numbers.isEmpty else { return (0, ScoreComponents()) }

        var averageComponents = ScoreComponents()
        var scoreSum = 0.0
        var counted = 0
        for number in numbers {
            guard let entry = context.scores[number] else { continue }
            scoreSum += entry.score
            averageComponents.frequency += entry.components.frequency
            averageComponents.recency += entry.components.recency
            averageComponents.delay += entry.components.delay
            averageComponents.trend += entry.components.trend
            averageComponents.stability += entry.components.stability
            counted += 1
        }
        guard counted > 0 else { return (0, ScoreComponents()) }
        let divisor = Double(counted)
        averageComponents.frequency /= divisor
        averageComponents.recency /= divisor
        averageComponents.delay /= divisor
        averageComponents.trend /= divisor
        averageComponents.stability /= divisor
        let averageScore = scoreSum / divisor

        averageComponents.coOccurrence = coOccurrenceScore(numbers, context: context)
        averageComponents.balance = balanceScore(numbers, context: context)

        let total = averageScore * weights.numberScore
            + averageComponents.coOccurrence * weights.coOccurrence
            + averageComponents.balance * weights.balance

        return (ScoringEngine.clamp(total), averageComponents)
    }

    /// Valutazione completa, spiegazioni incluse.
    static func evaluate(_ numbers: [Int],
                         context: AnalysisContext,
                         weights: CombinationWeights = .default) -> ScoredCombination {
        let sorted = numbers.sorted()
        guard !sorted.isEmpty else {
            return ScoredCombination(numbers: [], score: 0, components: ScoreComponents(), reasons: [])
        }
        let result = rawScore(sorted, context: context, weights: weights)
        let reasons = explain(sorted, context: context, components: result.components)
        return ScoredCombination(numbers: sorted,
                                 score: result.score,
                                 components: result.components,
                                 reasons: reasons)
    }

    /// Media dei lift (osservato/atteso) di tutte le coppie interne, mappata su 0–100.
    static func coOccurrenceScore(_ numbers: [Int], context: AnalysisContext) -> Double {
        guard numbers.count >= 2 else { return 50 }
        var lifts: [Double] = []
        for i in 0..<(numbers.count - 1) {
            for j in (i + 1)..<numbers.count {
                lifts.append(context.occurrences.pairLift(numbers[i], numbers[j]))
            }
        }
        guard !lifts.isEmpty else { return 50 }
        let mean = lifts.reduce(0, +) / Double(lifts.count)
        // lift 1.0 (perfettamente in media) -> 50 punti.
        return ScoringEngine.clamp(50 * mean)
    }

    /// Quanto la combinazione è "tipica" rispetto alle distribuzioni storiche:
    /// somma, parità, basso/alto, dispersione fra decine, numeri consecutivi.
    static func balanceScore(_ numbers: [Int], context: AnalysisContext) -> Double {
        let count = numbers.count
        guard count >= 2 else { return 50 }

        let sum = Double(numbers.reduce(0, +))
        // Somma attesa proporzionata alla dimensione della combinazione.
        let expectedSum = context.sumMean / Double(context.game.drawnCount) * Double(count)
        let expectedSigma = context.sumStandardDeviation / Double(context.game.drawnCount).squareRoot()
            * Double(count).squareRoot()
        let sumZ = expectedSigma > 0 ? abs(sum - expectedSum) / expectedSigma : 0
        let sumScore = 100 * exp(-pow(sumZ, 2) / 2)

        let even = numbers.filter { $0 % 2 == 0 }.count
        let parityDeviation = abs(Double(even) - Double(count) / 2) / (Double(count) / 2)
        let parityScore = 100 * (1 - min(parityDeviation, 1))

        let low = numbers.filter { $0 <= 45 }.count
        let rangeDeviation = abs(Double(low) - Double(count) / 2) / (Double(count) / 2)
        let rangeScore = 100 * (1 - min(rangeDeviation, 1))

        let decades = Set(numbers.map { min(($0 - 1) / 10, 8) }).count
        let decadeScore = 100 * Double(decades) / Double(min(count, 9))

        let sortedNumbers = numbers.sorted()
        var consecutive = 0
        for index in 1..<sortedNumbers.count where sortedNumbers[index] == sortedNumbers[index - 1] + 1 {
            consecutive += 1
        }
        // Una coppia consecutiva è normale, tre o più sono un pattern raro.
        let consecutivePenalty = Double(max(consecutive - 1, 0)) * 15

        let raw = sumScore * 0.30 + parityScore * 0.20 + rangeScore * 0.20 + decadeScore * 0.30
        return ScoringEngine.clamp(raw - consecutivePenalty)
    }

    // MARK: - Spiegazioni

    static func explain(_ numbers: [Int],
                        context: AnalysisContext,
                        components: ScoreComponents) -> [String] {
        var reasons: [String] = []

        let stats = numbers.map { context.stats(of: $0) }
        let hottest = stats.max { $0.trendRatio < $1.trendRatio }
        let mostOverdue = stats.max { $0.currentDelay < $1.currentDelay }
        let mostFrequent = stats.max { $0.occurrences < $1.occurrences }

        if let mostFrequent, mostFrequent.occurrences > 0 {
            reasons.append(String(format: "Il %02d è il numero più frequente della combinazione: %d uscite su %d estrazioni (%.1f%% contro un atteso del %.1f%%).",
                                  mostFrequent.number,
                                  mostFrequent.occurrences,
                                  context.drawCount,
                                  mostFrequent.frequency * 100,
                                  mostFrequent.expectedFrequency * 100))
        }
        if let mostOverdue, mostOverdue.currentDelay > 0 {
            reasons.append(String(format: "Il %02d manca da %d estrazioni, con un ritardo medio storico di %.1f e un massimo di %d.",
                                  mostOverdue.number,
                                  mostOverdue.currentDelay,
                                  mostOverdue.averageDelay,
                                  mostOverdue.maxDelay))
        }
        if let hottest, hottest.trendRatio > 1.05 {
            reasons.append(String(format: "Il %02d mostra una frequenza recente superiore del %.0f%% rispetto alla sua frequenza nel periodo.",
                                  hottest.number, (hottest.trendRatio - 1) * 100))
        }

        if numbers.count >= 2 {
            var best: (a: Int, b: Int, lift: Double, count: Int)?
            for i in 0..<(numbers.count - 1) {
                for j in (i + 1)..<numbers.count {
                    let lift = context.occurrences.pairLift(numbers[i], numbers[j])
                    if best == nil || lift > best!.lift {
                        best = (numbers[i], numbers[j], lift, context.occurrences.pairCount(numbers[i], numbers[j]))
                    }
                }
            }
            if let best, best.count > 0 {
                if best.lift >= 1.15 {
                    reasons.append(String(format: "La coppia %02d–%02d è uscita insieme %d volte, il %.0f%% in più di quanto atteso dal caso.",
                                          best.a, best.b, best.count, (best.lift - 1) * 100))
                } else {
                    reasons.append(String(format: "La coppia più ricorrente è %02d–%02d con %d uscite congiunte (in linea con l'atteso).",
                                          best.a, best.b, best.count))
                }
            }
        }

        let sum = numbers.reduce(0, +)
        let even = numbers.filter { $0 % 2 == 0 }.count
        let low = numbers.filter { $0 <= 45 }.count
        reasons.append(String(format: "Distribuzione: %d pari / %d dispari, %d nella fascia 1–45 e %d nella 46–90, somma %d (media storica %.0f).",
                              even, numbers.count - even, low, numbers.count - low, sum, context.sumMean / Double(context.game.drawnCount) * Double(numbers.count)))

        if components.balance >= 70 {
            reasons.append("L'equilibrio complessivo della combinazione è in linea con le distribuzioni storiche osservate.")
        } else if components.balance < 40 {
            reasons.append("La combinazione è distribuita in modo atipico rispetto allo storico: somma o parità lontane dai valori più frequenti.")
        }

        reasons.append(Disclaimer.explainer)
        return reasons
    }
}
