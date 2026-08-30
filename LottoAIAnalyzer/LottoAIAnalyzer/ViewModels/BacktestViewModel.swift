import Foundation
import Observation

@MainActor
@Observable
final class BacktestViewModel {

    var game: GameType
    var wheel: Wheel
    var kind: BacktestStrategyKind = .pairs
    var mode: QuintupleMode = .balanced
    var lookback: AnalysisPeriod = .fiveYears
    var startDate: Date
    var endDate: Date
    var playsPerDraw = 3
    var stake: Double = 1

    var result: BacktestResult?
    var validation: ValidationReport?
    var isRunning = false
    var progress: Double = 0
    var errorMessage: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        self.game = app.settings.defaultGame
        self.wheel = app.settings.defaultWheel
        let calendar = Calendar.italian
        let now = Date()
        self.endDate = now
        self.startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
    }

    var configuration: BacktestConfiguration {
        BacktestConfiguration(game: game,
                              wheel: game.usesWheels ? wheel : nil,
                              lookback: lookback,
                              startDate: startDate,
                              endDate: endDate,
                              kind: kind,
                              mode: mode,
                              playsPerDraw: playsPerDraw,
                              stakePerPlay: stake,
                              payouts: app.settings.payouts(for: game),
                              weights: app.settings.weights,
                              seed: 7,
                              candidatePoolSize: 40,
                              minimumHistory: 60)
    }

    func run() async {
        isRunning = true
        progress = 0
        errorMessage = nil
        defer { isRunning = false }

        let configuration = self.configuration
        let draws = app.draws(for: game)
        guard !draws.isEmpty else {
            errorMessage = "Nessuna estrazione disponibile per \(game.displayName)."
            return
        }

        result = await app.compute {
            BacktestEngine.run(configuration: configuration, allDraws: draws, progress: nil)
        }
        progress = 1
        if result?.drawsEvaluated == 0 {
            errorMessage = "Nel periodo scelto non ci sono abbastanza estrazioni precedenti per applicare la strategia (servono almeno \(configuration.minimumHistory) estrazioni di storico)."
        }
    }

    /// Esegue l'intera batteria di validazione (backtest + walk-forward + Monte Carlo + ML).
    func runValidation() async {
        isRunning = true
        progress = 0
        errorMessage = nil
        defer { isRunning = false }

        let configuration = self.configuration
        let draws = app.draws(for: game)
        guard !draws.isEmpty else {
            errorMessage = "Nessuna estrazione disponibile."
            return
        }
        let report = await app.compute {
            ValidationEngine.validate(configuration: configuration, allDraws: draws, folds: 4, includeML: true)
        }
        validation = report
        result = report.backtest
        progress = 1
    }

    // MARK: - Serie per i grafici

    /// Andamento cumulato del saldo teorico.
    var equityCurve: [EquityPoint] {
        guard let result else { return [] }
        var cumulative = 0.0
        return result.steps.map { step in
            cumulative += step.net
            return EquityPoint(date: step.date, value: cumulative)
        }
    }

    var hitDistribution: [HitBucket] {
        guard let result else { return [] }
        let keys = Set(result.strategy.hitDistribution.keys).union(result.baseline.hitDistribution.keys).sorted()
        return keys.map { HitBucket(matched: $0,
                                    strategy: result.strategy.hits($0),
                                    baseline: result.baseline.hits($0)) }
    }
}

/// Punto della curva del saldo teorico cumulato.
struct EquityPoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Confronto strategia/baseline per numero di numeri indovinati.
struct HitBucket: Identifiable, Sendable {
    let matched: Int
    let strategy: Int
    let baseline: Int
    var id: Int { matched }
}
