import Foundation

/// Vincoli statistici che una combinazione generata deve rispettare.
struct CombinationConstraints: Sendable {
    var minSum: Int
    var maxSum: Int
    var minEven: Int
    var maxEven: Int
    var minLow: Int
    var maxLow: Int
    var minDistinctDecades: Int
    var maxConsecutivePairs: Int

    /// Vincoli derivati dalle distribuzioni storiche effettivamente osservate.
    static func derived(from context: AnalysisContext, size: Int) -> CombinationConstraints {
        let scale = Double(size) / Double(max(context.game.drawnCount, 1))
        let mean = context.sumMean * scale
        let sigma = context.sumStandardDeviation * scale.squareRoot()
        let half = Double(size) / 2
        return CombinationConstraints(
            minSum: max(Int(mean - 1.5 * sigma), size),
            maxSum: min(Int(mean + 1.5 * sigma), size * 90),
            minEven: max(Int((half - 1.5).rounded(.down)), 0),
            maxEven: min(Int((half + 1.5).rounded(.up)), size),
            minLow: max(Int((half - 1.5).rounded(.down)), 0),
            maxLow: min(Int((half + 1.5).rounded(.up)), size),
            minDistinctDecades: max(size - 1, 2),
            maxConsecutivePairs: 1)
    }

    /// Vincoli rilassati, usati quando il campionamento non trova candidati validi.
    func relaxed() -> CombinationConstraints {
        var copy = self
        let span = maxSum - minSum
        copy.minSum = max(minSum - span / 4, 1)
        copy.maxSum = maxSum + span / 4
        copy.minEven = max(minEven - 1, 0)
        copy.maxEven = maxEven + 1
        copy.minLow = max(minLow - 1, 0)
        copy.maxLow = maxLow + 1
        copy.minDistinctDecades = max(minDistinctDecades - 1, 1)
        copy.maxConsecutivePairs = maxConsecutivePairs + 1
        return copy
    }

    func isSatisfied(by numbers: [Int]) -> Bool {
        let sum = numbers.reduce(0, +)
        guard (minSum...maxSum).contains(sum) else { return false }
        let even = numbers.filter { $0 % 2 == 0 }.count
        guard (minEven...maxEven).contains(even) else { return false }
        let low = numbers.filter { $0 <= 45 }.count
        guard (minLow...maxLow).contains(low) else { return false }
        let decades = Set(numbers.map { min(($0 - 1) / 10, 8) }).count
        guard decades >= min(minDistinctDecades, numbers.count) else { return false }
        let sorted = numbers.sorted()
        var consecutive = 0
        for index in 1..<sorted.count where sorted[index] == sorted[index - 1] + 1 { consecutive += 1 }
        return consecutive <= maxConsecutivePairs
    }
}

/// **CINQUINA AI** — generatore di combinazioni complete (5 numeri per il Lotto,
/// 6 per il SuperEnalotto).
///
/// Le C(90,5) = 43.949.268 cinquine possibili non sono enumerabili: si usa un
/// campionamento pesato dagli indici statistici, filtrato dai vincoli storici e
/// affinato da una ricerca locale.
enum QuintupleGenerator {

    struct Request: Sendable {
        var context: AnalysisContext
        var mode: QuintupleMode = .balanced
        var strategy: GenerationStrategy?
        var size: Int?
        var count: Int = 5
        var seed: UInt64 = 0
        /// Combinazioni da cui differenziarsi (modalità Diversificata).
        var avoid: [[Int]] = []
        var candidateSamples: Int = 4000
    }

    static func generate(_ request: Request) -> [ScoredCombination] {
        let context = request.context
        guard !context.isEmpty else { return [] }
        let size = request.size ?? context.game.drawnCount
        let strategy = request.strategy ?? request.mode.strategy
        var generator = SeededRandom(seed: request.seed == 0 ? UInt64(Date().timeIntervalSince1970 * 1000) : request.seed)

        let weights = samplingWeights(context: context, strategy: strategy)
        var constraints = CombinationConstraints.derived(from: context, size: size)

        var selected: [ScoredCombination] = []
        var avoidSets = request.avoid.map(Set.init)
        var attemptsWithoutResult = 0

        while selected.count < request.count {
            var candidates: [ScoredCombination] = []
            candidates.reserveCapacity(64)

            for _ in 0..<request.candidateSamples {
                let indices = generator.weightedSample(weights: weights, count: size)
                guard indices.count == size else { continue }
                let numbers = indices.map { $0 + context.game.numberRange.lowerBound }.sorted()
                guard constraints.isSatisfied(by: numbers) else { continue }
                let evaluation = CombinationEngine.rawScore(numbers, context: context)
                var score = evaluation.score
                // Penalità di sovrapposizione con le combinazioni già scelte.
                let overlapPenalty = overlap(numbers, with: avoidSets)
                score -= overlapPenalty * (request.mode == .diversified ? 12 : 4)
                candidates.append(ScoredCombination(numbers: numbers,
                                                    score: ScoringEngine.clamp(score),
                                                    components: evaluation.components,
                                                    reasons: []))
                if candidates.count >= 400 { break }
            }

            guard let best = candidates.max(by: { $0.score < $1.score }) else {
                attemptsWithoutResult += 1
                if attemptsWithoutResult > 3 { break }
                constraints = constraints.relaxed()
                continue
            }
            attemptsWithoutResult = 0

            let refined = localSearch(best,
                                      context: context,
                                      constraints: constraints,
                                      avoid: avoidSets,
                                      diversify: request.mode == .diversified)
            guard !selected.contains(where: { $0.numbers == refined.numbers }) else {
                constraints = constraints.relaxed()
                continue
            }
            var finalized = refined
            finalized.reasons = CombinationEngine.explain(refined.numbers,
                                                          context: context,
                                                          components: refined.components)
            finalized.reasons.insert(strategyLine(for: request.mode, strategy: strategy), at: 0)
            selected.append(finalized)
            avoidSets.append(Set(refined.numbers))
        }

        return selected.sorted { $0.score > $1.score }
    }

    // MARK: - Pesi di campionamento

    static func samplingWeights(context: AnalysisContext, strategy: GenerationStrategy) -> [Double] {
        let range = context.game.numberRange
        return range.map { number -> Double in
            let stats = context.stats(of: number)
            let score = context.score(of: number)
            let base: Double
            switch strategy {
            case .frequency:
                base = Double(stats.occurrences) + 1
            case .delay:
                base = Double(stats.currentDelay) + 1
            case .hot:
                base = stats.isHot ? score + 20 : max(score - 30, 1)
            case .cold:
                base = stats.isCold ? score + 20 : max(score - 30, 1)
            case .trend:
                base = ScoringEngine.trendScore(stats.trendRatio) + 1
            case .statisticalRandom:
                base = 1
            case .conservative:
                base = pow(max(score, 1), 2) / 50
            default:
                base = max(score, 1)
            }
            return max(base, 0.1)
        }
    }

    // MARK: - Ricerca locale

    /// Prova a sostituire un numero alla volta per migliorare l'indice statistico.
    static func localSearch(_ combination: ScoredCombination,
                            context: AnalysisContext,
                            constraints: CombinationConstraints,
                            avoid: [Set<Int>],
                            diversify: Bool,
                            iterations: Int = 3) -> ScoredCombination {
        var current = combination
        let pool = context.topNumbers(45)

        for _ in 0..<iterations {
            var improved = false
            for position in current.numbers.indices {
                for replacement in pool where !current.numbers.contains(replacement) {
                    var candidate = current.numbers
                    candidate[position] = replacement
                    candidate.sort()
                    guard constraints.isSatisfied(by: candidate) else { continue }
                    let evaluation = CombinationEngine.rawScore(candidate, context: context)
                    var score = evaluation.score
                    score -= overlap(candidate, with: avoid) * (diversify ? 12 : 4)
                    if score > current.score + 0.01 {
                        current = ScoredCombination(numbers: candidate,
                                                    score: ScoringEngine.clamp(score),
                                                    components: evaluation.components,
                                                    reasons: [])
                        improved = true
                        break
                    }
                }
                if improved { break }
            }
            if !improved { break }
        }
        return current
    }

    private static func overlap(_ numbers: [Int], with sets: [Set<Int>]) -> Double {
        guard !sets.isEmpty else { return 0 }
        let candidate = Set(numbers)
        let maximum = sets.map { Double($0.intersection(candidate).count) }.max() ?? 0
        return maximum
    }

    private static func strategyLine(for mode: QuintupleMode, strategy: GenerationStrategy) -> String {
        "Modalità \(mode.displayName): \(strategy.explanation)"
    }
}
