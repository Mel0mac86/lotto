import Foundation

/// Moltiplicatori teorici usati per calcolare le vincite simulate.
///
/// Per il Lotto corrispondono ai moltiplicatori ufficiali lordi per posta unitaria
/// su una singola ruota. Per il SuperEnalotto le vincite sono a totalizzatore e
/// variano a ogni concorso: i valori qui sono **indicativi** e configurabili.
struct PayoutTable: Codable, Hashable, Sendable {
    /// [numeri indovinati: moltiplicatore della posta]
    var multipliers: [Int: Double]

    static let lotto = PayoutTable(multipliers: [
        1: 11.232,
        2: 250,
        3: 4_500,
        4: 120_000,
        5: 6_000_000
    ])

    static let superenalotto = PayoutTable(multipliers: [
        2: 5,
        3: 30,
        4: 300,
        5: 30_000,
        6: 2_000_000
    ])

    static func `default`(for game: GameType) -> PayoutTable {
        game == .lotto ? .lotto : .superenalotto
    }

    func payout(matched: Int, stake: Double) -> Double {
        (multipliers[matched] ?? 0) * stake
    }
}

/// Tipo di giocata simulata.
enum BacktestStrategyKind: String, CaseIterable, Identifiable, Sendable {
    case pairs
    case triples
    case quintuples
    case randomBaseline

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pairs: return "Top ambi"
        case .triples: return "Top terni"
        case .quintuples: return "Cinquina AI"
        case .randomBaseline: return "Baseline casuale"
        }
    }

    /// Numeri per giocata.
    func size(for game: GameType) -> Int {
        switch self {
        case .pairs: return 2
        case .triples: return 3
        case .quintuples, .randomBaseline: return game.drawnCount
        }
    }

    /// Numeri indovinati minimi perché la giocata sia considerata "centrata".
    var winningThreshold: Int {
        switch self {
        case .pairs: return 2
        case .triples: return 3
        case .quintuples, .randomBaseline: return 2
        }
    }
}

/// Configurazione di un backtest walk-forward.
struct BacktestConfiguration: Sendable {
    var game: GameType = .lotto
    var wheel: Wheel? = .bari
    /// Finestra storica usata a ogni passo (guarda solo indietro).
    var lookback: AnalysisPeriod = .fiveYears
    var startDate: Date
    var endDate: Date
    var kind: BacktestStrategyKind = .pairs
    var mode: QuintupleMode = .balanced
    var playsPerDraw: Int = 3
    var stakePerPlay: Double = 1
    var payouts: PayoutTable = .lotto
    var weights: ScoringWeights = .balanced
    var seed: UInt64 = 7
    /// Numeri considerati nella generazione (riduce il costo computazionale).
    var candidatePoolSize: Int = 40
    /// Estrazioni minime richieste prima di iniziare a giocare.
    var minimumHistory: Int = 60
}

/// Un passo del backtest: una singola estrazione simulata.
struct BacktestStep: Identifiable, Sendable {
    let date: Date
    let wheel: Wheel?
    let drawnNumbers: [Int]
    let plays: [[Int]]
    let matches: [Int]
    let cost: Double
    let winnings: Double

    var id: String { "\(date.timeIntervalSince1970)-\(wheel?.rawValue ?? "-")" }
    var bestMatch: Int { matches.max() ?? 0 }
    var net: Double { winnings - cost }
}

/// Statistiche aggregate di una serie di giocate.
struct BacktestSummary: Sendable {
    var totalPlays: Int = 0
    var totalCost: Double = 0
    var totalWinnings: Double = 0
    /// [numeri indovinati: quante giocate]
    var hitDistribution: [Int: Int] = [:]
    var winningPlays: Int = 0

    var net: Double { totalWinnings - totalCost }
    var roi: Double { totalCost > 0 ? net / totalCost * 100 : 0 }
    var hitRate: Double { totalPlays > 0 ? Double(winningPlays) / Double(totalPlays) : 0 }

    func hits(_ matched: Int) -> Int { hitDistribution[matched] ?? 0 }
}

/// Risultato completo del backtest.
struct BacktestResult: Sendable {
    var configuration: BacktestConfiguration
    var steps: [BacktestStep]
    var strategy: BacktestSummary
    var baseline: BacktestSummary
    var significance: TestResult
    var drawsEvaluated: Int
    var elapsed: TimeInterval

    /// Verdetto onesto sul confronto con la casualità.
    var verdict: String {
        if drawsEvaluated == 0 {
            return "Dati insufficienti nel periodo selezionato per eseguire il backtest."
        }
        if !significance.isSignificant {
            return "\(Disclaimer.noEdge) Nel periodo testato la strategia non ha prodotto una differenza statisticamente significativa rispetto a giocate casuali."
        }
        return strategy.hitRate > baseline.hitRate
            ? "Nel campione analizzato la strategia mostra una differenza statisticamente significativa rispetto alla baseline casuale. Il risultato riguarda esclusivamente il periodo testato e non dimostra capacità predittiva su estrazioni future."
            : "Nel campione analizzato la strategia ha ottenuto risultati significativamente peggiori della baseline casuale."
    }
}

/// **BACKTESTING walk-forward**.
///
/// A ogni passo il motore ricostruisce le statistiche usando **soltanto** le
/// estrazioni con data strettamente precedente a quella simulata
/// (`AnalysisFilter.cutoffDate`). Non esiste alcun percorso che permetta ai dati
/// futuri di entrare nel calcolo: è la protezione contro il data leakage.
enum BacktestEngine {

    static func run(configuration: BacktestConfiguration,
                    allDraws: [DrawRecord],
                    progress: (@Sendable (Double) -> Void)? = nil) -> BacktestResult {
        let start = Date()
        let gameDraws = allDraws
            .filter { $0.game == configuration.game }
            .filter { configuration.game.usesWheels ? $0.wheel == configuration.wheel : true }
            .sorted { $0.date < $1.date }

        let testDraws = gameDraws.filter { $0.date >= configuration.startDate && $0.date <= configuration.endDate }
        var steps: [BacktestStep] = []
        var strategySummary = BacktestSummary()
        var baselineSummary = BacktestSummary()
        var generator = SeededRandom(seed: configuration.seed)
        let size = configuration.kind.size(for: configuration.game)

        for (index, target) in testDraws.enumerated() {
            progress?(Double(index) / Double(max(testDraws.count, 1)))

            // ---- Barriera anti data-leakage -------------------------------
            // Vengono usate solo le estrazioni con data < target.date.
            var filter = AnalysisFilter(game: configuration.game,
                                        wheelScope: configuration.wheel.map { WheelScope.single($0) } ?? .all,
                                        period: configuration.lookback,
                                        calendarYear: nil,
                                        cutoffDate: target.date)
            filter.calendarYear = nil
            let history = StatisticsEngine.apply(filter, to: gameDraws)
            guard history.count >= configuration.minimumHistory else { continue }
            // ---------------------------------------------------------------

            let context = AnalysisContext(filter: filter, allDraws: gameDraws, weights: configuration.weights)
            let plays = generatePlays(configuration: configuration,
                                      context: context,
                                      generator: &generator)
            guard !plays.isEmpty else { continue }

            let drawn = Set(target.numbers)
            var matches: [Int] = []
            var stepWinnings = 0.0
            let stepCost = Double(plays.count) * configuration.stakePerPlay

            for play in plays {
                let matched = play.filter { drawn.contains($0) }.count
                matches.append(matched)
                strategySummary.totalPlays += 1
                strategySummary.hitDistribution[matched, default: 0] += 1
                if matched >= configuration.kind.winningThreshold { strategySummary.winningPlays += 1 }
                // Una giocata di k numeri vince se ne indovina almeno la sorte minima.
                let payout = configuration.payouts.payout(matched: matched, stake: configuration.stakePerPlay)
                stepWinnings += payout
            }
            strategySummary.totalCost += stepCost
            strategySummary.totalWinnings += stepWinnings

            // Baseline: stesse dimensioni e stesso numero di giocate, numeri casuali.
            for _ in plays {
                let random = randomPlay(size: size, generator: &generator)
                let matched = random.filter { drawn.contains($0) }.count
                baselineSummary.totalPlays += 1
                baselineSummary.hitDistribution[matched, default: 0] += 1
                if matched >= configuration.kind.winningThreshold { baselineSummary.winningPlays += 1 }
                baselineSummary.totalWinnings += configuration.payouts.payout(matched: matched, stake: configuration.stakePerPlay)
            }
            baselineSummary.totalCost += stepCost

            steps.append(BacktestStep(date: target.date,
                                      wheel: target.wheel,
                                      drawnNumbers: target.numbers,
                                      plays: plays,
                                      matches: matches,
                                      cost: stepCost,
                                      winnings: stepWinnings))
        }
        progress?(1)

        let significance = StatisticalTests.twoProportionZTest(
            successesA: strategySummary.winningPlays,
            trialsA: strategySummary.totalPlays,
            successesB: baselineSummary.winningPlays,
            trialsB: baselineSummary.totalPlays,
            name: "Strategia contro baseline casuale")

        return BacktestResult(configuration: configuration,
                              steps: steps,
                              strategy: strategySummary,
                              baseline: baselineSummary,
                              significance: significance,
                              drawsEvaluated: steps.count,
                              elapsed: Date().timeIntervalSince(start))
    }

    // MARK: - Generazione delle giocate

    private static func generatePlays(configuration: BacktestConfiguration,
                                      context: AnalysisContext,
                                      generator: inout SeededRandom) -> [[Int]] {
        switch configuration.kind {
        case .pairs:
            let pool = Set(context.topNumbers(configuration.candidatePoolSize))
            return PairGenerator.topPairs(context: context,
                                          limit: configuration.playsPerDraw,
                                          restrictedTo: pool).map(\.numbers)
        case .triples:
            return TripleGenerator.topTriples(context: context,
                                              limit: configuration.playsPerDraw,
                                              poolSize: configuration.candidatePoolSize).map(\.numbers)
        case .quintuples:
            let request = QuintupleGenerator.Request(context: context,
                                                     mode: configuration.mode,
                                                     strategy: nil,
                                                     size: nil,
                                                     count: configuration.playsPerDraw,
                                                     seed: generator.next(),
                                                     avoid: [],
                                                     candidateSamples: 1500)
            return QuintupleGenerator.generate(request).map(\.numbers)
        case .randomBaseline:
            let size = configuration.kind.size(for: configuration.game)
            return (0..<configuration.playsPerDraw).map { _ in randomPlay(size: size, generator: &generator) }
        }
    }

    private static func randomPlay(size: Int, generator: inout SeededRandom) -> [Int] {
        var pool = Array(1...90)
        for position in 0..<size {
            let swapIndex = position + Int(generator.next() % UInt64(90 - position))
            pool.swapAt(position, swapIndex)
        }
        return Array(pool.prefix(size)).sorted()
    }
}
