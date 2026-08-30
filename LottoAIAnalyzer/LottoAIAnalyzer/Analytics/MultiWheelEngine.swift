import Foundation

/// Sintesi multi-ruota per un singolo numero.
struct MultiWheelNumber: Hashable, Identifiable, Sendable {
    let number: Int
    /// Ruote su cui il numero mostra un indice statistico sopra la soglia.
    var wheels: [Wheel]
    /// Uscite complessive su tutte le ruote.
    var totalOccurrences: Int
    /// Media degli indici statistici sulle ruote in cui è segnalato.
    var averageScore: Double
    /// Score complessivo che tiene conto anche del numero di ruote coinvolte.
    var score: Double
    /// Ritardo medio sulle ruote analizzate.
    var averageDelay: Double
    /// Ruota su cui il segnale è più forte.
    var bestWheel: Wheel?

    var id: Int { number }
    var wheelCodes: String { wheels.map(\.shortCode).joined(separator: " ") }
    var band: ScoreBand { ScoreBand(score: score) }
}

/// Ambo o terno che ricorre su più ruote.
struct MultiWheelSet: Hashable, Identifiable, Sendable {
    let numbers: [Int]
    /// Ruote in cui l'insieme è uscito almeno una volta.
    var wheels: [Wheel]
    var totalJointCount: Int
    var recentJointCount: Int
    var averageDelay: Double
    var score: Double
    var reasons: [String] = []

    var id: String { numbers.map(String.init).joined(separator: "-") }
    var formatted: String { numbers.map { String(format: "%02d", $0) }.joined(separator: " – ") }
    var wheelCount: Int { wheels.count }
    var band: ScoreBand { ScoreBand(score: score) }
}

/// Analisi **TUTTE LE RUOTE**: cerca i numeri e le combinazioni che mostrano
/// segnali statistici coerenti su più ruote contemporaneamente.
enum MultiWheelEngine {

    /// Contesto per ruota, costruito una sola volta e riusato da tutte le funzioni.
    struct WheelContexts: Sendable {
        var contexts: [Wheel: AnalysisContext]

        var wheels: [Wheel] { contexts.keys.sorted { $0.rawValue < $1.rawValue } }
        var isEmpty: Bool { contexts.isEmpty }
    }

    static func buildContexts(filter: AnalysisFilter,
                              allDraws: [DrawRecord],
                              weights: ScoringWeights) -> WheelContexts {
        var contexts: [Wheel: AnalysisContext] = [:]
        for wheel in Wheel.allCases {
            var wheelFilter = filter
            wheelFilter.wheelScope = .single(wheel)
            let context = AnalysisContext(filter: wheelFilter, allDraws: allDraws, weights: weights)
            if !context.isEmpty { contexts[wheel] = context }
        }
        return WheelContexts(contexts: contexts)
    }

    // MARK: - Numeri multi-ruota

    static func numbers(from wheelContexts: WheelContexts,
                        scoreThreshold: Double = 65,
                        limit: Int = 30) -> [MultiWheelNumber] {
        guard !wheelContexts.isEmpty else { return [] }
        var results: [MultiWheelNumber] = []
        let totalWheels = Double(wheelContexts.contexts.count)

        for number in 1...90 {
            var wheels: [Wheel] = []
            var scoreSum = 0.0
            var occurrences = 0
            var delaySum = 0.0
            var best: (wheel: Wheel, score: Double)?

            for (wheel, context) in wheelContexts.contexts {
                let score = context.score(of: number)
                let stats = context.stats(of: number)
                occurrences += stats.occurrences
                delaySum += Double(stats.currentDelay)
                if score >= scoreThreshold {
                    wheels.append(wheel)
                    scoreSum += score
                }
                if best == nil || score > best!.score { best = (wheel, score) }
            }

            guard !wheels.isEmpty else { continue }
            let averageScore = scoreSum / Double(wheels.count)
            // Il bonus multi-ruota premia la coerenza del segnale, non la sua forza su una sola ruota.
            let coverage = Double(wheels.count) / totalWheels
            let score = ScoringEngine.clamp(averageScore * 0.7 + coverage * 100 * 0.3)

            results.append(MultiWheelNumber(number: number,
                                            wheels: wheels.sorted { $0.rawValue < $1.rawValue },
                                            totalOccurrences: occurrences,
                                            averageScore: averageScore,
                                            score: score,
                                            averageDelay: delaySum / totalWheels,
                                            bestWheel: best?.wheel))
        }

        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: - Ambi multi-ruota

    static func pairs(from wheelContexts: WheelContexts, limit: Int = 10) -> [MultiWheelSet] {
        guard !wheelContexts.isEmpty else { return [] }
        var aggregate = [Int: (wheels: Set<Wheel>, count: Int, recent: Int, delaySum: Double, scoreSum: Double)]()

        for (wheel, context) in wheelContexts.contexts {
            let recentWindow = max(min(context.drawCount, 20), context.drawCount / 4)
            let recentDraws = Array(context.draws.suffix(recentWindow))
            var recentCounts = [Int: Int]()
            for draw in recentDraws {
                let numbers = draw.numbers
                guard numbers.count >= 2 else { continue }
                for i in 0..<(numbers.count - 1) {
                    for j in (i + 1)..<numbers.count {
                        recentCounts[CoOccurrenceMatrix.index(numbers[i], numbers[j]), default: 0] += 1
                    }
                }
            }

            for index in 0..<CoOccurrenceMatrix.pairCount {
                let (a, b) = CoOccurrenceMatrix.pair(at: index)
                let count = context.occurrences.pairCount(a, b)
                guard count > 0 else { continue }
                var entry = aggregate[index] ?? (Set<Wheel>(), 0, 0, 0, 0)
                entry.wheels.insert(wheel)
                entry.count += count
                entry.recent += recentCounts[index] ?? 0
                entry.delaySum += Double(context.occurrences.pairDelay(a, b))
                entry.scoreSum += (context.score(of: a) + context.score(of: b)) / 2
                aggregate[index] = entry
            }
        }

        let totalWheels = Double(wheelContexts.contexts.count)
        var results: [MultiWheelSet] = []
        results.reserveCapacity(aggregate.count)

        for (index, entry) in aggregate {
            let (a, b) = CoOccurrenceMatrix.pair(at: index)
            let wheelCoverage = Double(entry.wheels.count) / totalWheels
            let averageNumberScore = entry.scoreSum / Double(entry.wheels.count)
            let expected = expectedPairCount(in: wheelContexts)
            let lift = expected > 0 ? Double(entry.count) / expected : 0
            let liftScore = ScoringEngine.clamp(50 * lift)
            let score = ScoringEngine.clamp(liftScore * 0.4 + averageNumberScore * 0.3 + wheelCoverage * 100 * 0.3)

            results.append(MultiWheelSet(numbers: [a, b],
                                         wheels: entry.wheels.sorted { $0.rawValue < $1.rawValue },
                                         totalJointCount: entry.count,
                                         recentJointCount: entry.recent,
                                         averageDelay: entry.delaySum / Double(entry.wheels.count),
                                         score: score))
        }

        return Array(results.sorted { $0.score > $1.score }.prefix(limit)).map { item in
            var enriched = item
            enriched.reasons = [
                "Uscita congiunta su \(item.wheelCount) ruote (\(item.wheels.map(\.shortCode).joined(separator: ", "))).",
                "Uscite congiunte complessive: \(item.totalJointCount), di cui \(item.recentJointCount) nella parte recente del periodo.",
                String(format: "Ritardo medio sulle ruote interessate: %.1f estrazioni.", item.averageDelay),
                Disclaimer.explainer
            ]
            return enriched
        }
    }

    // MARK: - Terni multi-ruota

    static func triples(from wheelContexts: WheelContexts, limit: Int = 10) -> [MultiWheelSet] {
        guard !wheelContexts.isEmpty else { return [] }
        var aggregate = [Int: (wheels: Set<Wheel>, count: Int, delaySum: Double, scoreSum: Double)]()

        for (wheel, context) in wheelContexts.contexts {
            for (key, entry) in context.occurrences.tripleCounts {
                var accumulated = aggregate[key] ?? (Set<Wheel>(), 0, 0, 0)
                accumulated.wheels.insert(wheel)
                accumulated.count += Int(entry.count)
                accumulated.delaySum += Double(context.drawCount - 1 - Int(entry.lastIndex))
                let numbers = decodeTriple(key)
                accumulated.scoreSum += numbers.map { context.score(of: $0) }.reduce(0, +) / 3
                aggregate[key] = accumulated
            }
        }

        let totalWheels = Double(wheelContexts.contexts.count)
        var buffer = TopKBuffer<MultiWheelSet>(capacity: limit) { $0.score > $1.score }

        for (key, entry) in aggregate {
            let numbers = decodeTriple(key)
            let coverage = Double(entry.wheels.count) / totalWheels
            let averageNumberScore = entry.scoreSum / Double(entry.wheels.count)
            let expected = expectedTripleCount(in: wheelContexts)
            let lift = expected > 0 ? Double(entry.count) / expected : 0
            let liftScore = ScoringEngine.clamp(50 * lift)
            let score = ScoringEngine.clamp(liftScore * 0.35 + averageNumberScore * 0.30 + coverage * 100 * 0.35)

            buffer.insert(MultiWheelSet(numbers: numbers,
                                        wheels: entry.wheels.sorted { $0.rawValue < $1.rawValue },
                                        totalJointCount: entry.count,
                                        recentJointCount: 0,
                                        averageDelay: entry.delaySum / Double(entry.wheels.count),
                                        score: score))
        }

        return buffer.sortedElements().map { item in
            var enriched = item
            enriched.reasons = [
                "Terna osservata su \(item.wheelCount) ruote (\(item.wheels.map(\.shortCode).joined(separator: ", "))).",
                "Uscite congiunte complessive su tutte le ruote: \(item.totalJointCount).",
                String(format: "Ritardo medio dall'ultima uscita: %.1f estrazioni.", item.averageDelay),
                Disclaimer.explainer
            ]
            return enriched
        }
    }

    // MARK: - Cinquina multi-ruota

    static func multiWheelCombination(from wheelContexts: WheelContexts,
                                      size: Int = 5,
                                      seed: UInt64 = 0) -> (combination: ScoredCombination, wheels: [Wheel])? {
        let candidates = numbers(from: wheelContexts, scoreThreshold: 60, limit: 25)
        guard candidates.count >= size else { return nil }

        // Il contesto della ruota con più estrazioni fa da riferimento per equilibrio e spiegazioni.
        guard let reference = wheelContexts.contexts.values.max(by: { $0.drawCount < $1.drawCount }) else { return nil }

        var generator = SeededRandom(seed: seed == 0 ? UInt64(Date().timeIntervalSince1970 * 1000) : seed)
        let constraints = CombinationConstraints.derived(from: reference, size: size)
        var best: (numbers: [Int], score: Double)?

        for _ in 0..<3000 {
            let weights = candidates.map { max($0.score, 1) }
            let indices = generator.weightedSample(weights: weights, count: size)
            guard indices.count == size else { continue }
            let numbers = indices.map { candidates[$0].number }.sorted()
            guard constraints.isSatisfied(by: numbers) else { continue }
            let multiWheelScore = numbers.compactMap { number in
                candidates.first { $0.number == number }?.score
            }.reduce(0, +) / Double(size)
            let balance = CombinationEngine.balanceScore(numbers, context: reference)
            let score = multiWheelScore * 0.75 + balance * 0.25
            if best == nil || score > best!.score { best = (numbers, score) }
        }

        guard let best else { return nil }
        let evaluation = CombinationEngine.rawScore(best.numbers, context: reference)
        let components = evaluation.components

        var reasons: [String] = ["Combinazione costruita sui numeri con segnali statistici presenti su più ruote."]
        var involvedWheels = Set<Wheel>()
        for number in best.numbers {
            guard let candidate = candidates.first(where: { $0.number == number }) else { continue }
            involvedWheels.formUnion(candidate.wheels)
            reasons.append(String(format: "%02d — segnalato su %d ruote (%@), indice medio %.0f.",
                                  number, candidate.wheels.count, candidate.wheelCodes, candidate.averageScore))
        }
        reasons.append(Disclaimer.explainer)

        let combination = ScoredCombination(numbers: best.numbers,
                                            score: ScoringEngine.clamp(best.score),
                                            components: components,
                                            reasons: reasons)
        return (combination, involvedWheels.sorted { $0.rawValue < $1.rawValue })
    }

    // MARK: - Helper

    private static func decodeTriple(_ key: Int) -> [Int] {
        let third = key % 91
        let second = (key / 91) % 91
        let first = key / (91 * 91)
        return [first, second, third]
    }

    private static func expectedPairCount(in contexts: WheelContexts) -> Double {
        contexts.contexts.values.reduce(0) { $0 + $1.occurrences.expectedPairCount }
    }

    private static func expectedTripleCount(in contexts: WheelContexts) -> Double {
        contexts.contexts.values.reduce(0) { $0 + $1.occurrences.expectedTripleCount }
    }
}
