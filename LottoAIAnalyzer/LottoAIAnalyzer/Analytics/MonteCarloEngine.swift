import Foundation

/// Risultato di una simulazione Monte Carlo.
struct MonteCarloResult: Sendable {
    var iterations: Int
    var drawnPerDraw: Int

    /// Frequenza simulata per numero (uscite / iterazioni).
    var simulatedFrequency: [Int: Double] = [:]
    /// Frequenza storica per numero, per il confronto.
    var historicalFrequency: [Int: Double] = [:]

    /// Istogramma delle somme: [somma: conteggio].
    var simulatedSums: [Int: Int] = [:]
    var historicalSums: [Int: Int] = [:]

    /// Distribuzione del numero di pari per estrazione.
    var simulatedEven: [Int: Int] = [:]
    var historicalEven: [Int: Int] = [:]

    /// Distribuzione delle uscite per decina.
    var simulatedDecades: [Int: Int] = [:]
    var historicalDecades: [Int: Int] = [:]

    /// Distribuzione dei ritardi massimi osservati.
    var simulatedMaxDelays: [Int] = []
    var historicalMaxDelays: [Int] = []

    var tests: [TestResult] = []
    var elapsed: TimeInterval = 0

    var conclusion: String {
        let significant = tests.filter(\.isSignificant)
        if significant.isEmpty {
            return "I pattern osservati nei dati storici sono compatibili con un processo casuale: nessuno dei test eseguiti ha rilevato scostamenti statisticamente significativi."
        }
        let names = significant.map(\.name).joined(separator: ", ")
        return "Alcuni test segnalano scostamenti dalla casualità (\(names)). Con molti test eseguiti in parallelo qualche scostamento è atteso anche in dati puramente casuali: va interpretato con prudenza e non implica capacità predittiva."
    }
}

/// Simulazioni Monte Carlo di estrazioni puramente casuali,
/// per confrontare i pattern storici con ciò che il caso produce.
enum MonteCarloEngine {

    enum Iterations: Int, CaseIterable, Identifiable, Sendable {
        case hundredThousand = 100_000
        case fiveHundredThousand = 500_000
        case million = 1_000_000

        var id: Int { rawValue }
        var displayName: String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "it_IT")
            return formatter.string(from: NSNumber(value: rawValue)) ?? "\(rawValue)"
        }
    }

    /// Esegue la simulazione. `progress` viene invocato con valori 0…1.
    static func run(context: AnalysisContext,
                    iterations: Int,
                    seed: UInt64 = 20260101,
                    progress: (@Sendable (Double) -> Void)? = nil) -> MonteCarloResult {
        let start = Date()
        let drawn = context.game.drawnCount
        var result = MonteCarloResult(iterations: iterations, drawnPerDraw: drawn)
        var generator = SeededRandom(seed: seed)

        var counts = [Int](repeating: 0, count: 91)
        var lastSeen = [Int](repeating: -1, count: 91)
        var maxDelays = [Int](repeating: 0, count: 91)
        // Gli accumulatori del ciclo caldo sono array: un dizionario qui costerebbe
        // milioni di hash su una simulazione da un milione di estrazioni.
        var decadeCounts = [Int](repeating: 0, count: 9)
        var sumCounts = [Int: Int]()
        var evenCounts = [Int](repeating: 0, count: 7)
        var pool = Array(1...90)
        let reportEvery = max(iterations / 100, 1)

        for iteration in 0..<iterations {
            // Estrazione senza reimmissione: Fisher–Yates parziale.
            for position in 0..<drawn {
                let swapIndex = position + Int(generator.next() % UInt64(90 - position))
                pool.swapAt(position, swapIndex)
            }
            var sum = 0
            var even = 0
            for position in 0..<drawn {
                let number = pool[position]
                counts[number] += 1
                sum += number
                if number % 2 == 0 { even += 1 }
                decadeCounts[min((number - 1) / 10, 8)] += 1
                if lastSeen[number] >= 0 {
                    maxDelays[number] = max(maxDelays[number], iteration - lastSeen[number] - 1)
                }
                lastSeen[number] = iteration
            }
            sumCounts[sum, default: 0] += 1
            if even < evenCounts.count { evenCounts[even] += 1 }

            if iteration % reportEvery == 0 {
                progress?(Double(iteration) / Double(iterations))
            }
        }
        progress?(1)

        result.simulatedSums = sumCounts
        for decade in 0..<9 { result.simulatedDecades[decade] = decadeCounts[decade] }
        for even in 0..<evenCounts.count where evenCounts[even] > 0 {
            result.simulatedEven[even] = evenCounts[even]
        }

        for number in 1...90 {
            result.simulatedFrequency[number] = Double(counts[number]) / Double(iterations)
            result.historicalFrequency[number] = context.stats(of: number).frequency
        }
        result.simulatedMaxDelays = Array(maxDelays[1...90])
        result.historicalMaxDelays = (1...90).map { context.stats(of: $0).maxDelay }

        for draw in context.draws {
            result.historicalSums[draw.sum, default: 0] += 1
            result.historicalEven[draw.evenCount, default: 0] += 1
            for number in draw.numbers {
                result.historicalDecades[min((number - 1) / 10, 8), default: 0] += 1
            }
        }

        result.tests = tests(for: context)
        result.elapsed = Date().timeIntervalSince(start)
        return result
    }

    /// Batteria di test sui dati storici, confrontati con il modello uniforme.
    static func tests(for context: AnalysisContext) -> [TestResult] {
        guard context.drawCount > 0 else { return [] }
        let drawn = Double(context.game.drawnCount)
        let totalNumbers = Double(context.drawCount) * drawn

        let observedFrequencies = (1...90).map { Double(context.stats(of: $0).occurrences) }
        let expectedFrequency = totalNumbers / 90
        let frequencyTest = StatisticalTests.chiSquareGoodnessOfFit(
            observed: observedFrequencies,
            expected: Array(repeating: expectedFrequency, count: 90),
            name: "Uniformità delle frequenze (1–90)")

        let observedDecades = (0...8).map { decade -> Double in
            Double(context.statistics.decadeDistribution[decade] ?? 0)
        }
        // Le decine hanno 10 numeri ciascuna tranne la nona (81–90 ne ha 10): tutte uguali.
        let decadeTest = StatisticalTests.chiSquareGoodnessOfFit(
            observed: observedDecades,
            expected: Array(repeating: totalNumbers / 9, count: 9),
            name: "Uniformità delle decine")

        // Ogni cifra delle unità (0…9) copre esattamente 9 numeri fra 1 e 90.
        let observedUnits = (0...9).map { Double(context.statistics.unitDistribution[$0] ?? 0) }
        let unitTest = StatisticalTests.chiSquareGoodnessOfFit(
            observed: observedUnits,
            expected: Array(repeating: totalNumbers / 10, count: 10),
            name: "Uniformità delle unità")

        // Parità: probabilità di un numero pari = 45/90 = 0.5.
        let totalEven = context.draws.reduce(0) { $0 + $1.evenCount }
        let parityTest = StatisticalTests.binomialTest(
            successes: totalEven,
            trials: Int(totalNumbers),
            probability: 0.5,
            name: "Distribuzione pari/dispari")

        let totalLow = context.draws.reduce(0) { $0 + $1.lowCount }
        let rangeTest = StatisticalTests.binomialTest(
            successes: totalLow,
            trials: Int(totalNumbers),
            probability: 0.5,
            name: "Distribuzione 1–45 / 46–90")

        return [frequencyTest, decadeTest, unitTest, parityTest, rangeTest]
    }
}
