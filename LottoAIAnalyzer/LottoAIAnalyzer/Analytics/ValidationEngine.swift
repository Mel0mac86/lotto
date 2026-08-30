import Foundation

/// Esito completo della validazione di un algoritmo.
struct ValidationReport: Sendable {
    var strategyName: String
    var backtest: BacktestResult?
    var walkForwardFolds: [FoldResult]
    var monteCarloTests: [TestResult]
    var mlEvaluation: MLEvaluation?
    var generatedAt: Date = Date()

    struct FoldResult: Identifiable, Sendable {
        let index: Int
        let start: Date
        let end: Date
        let hitRate: Double
        let baselineHitRate: Double
        let plays: Int

        var id: Int { index }
        var difference: Double { hitRate - baselineHitRate }
    }

    /// Verdetto finale. È volutamente conservativo: dichiara un vantaggio solo se
    /// tutti i controlli lo confermano.
    var verdict: String {
        guard let backtest, backtest.drawsEvaluated > 0 else {
            return "Validazione non eseguibile: dati storici insufficienti nel periodo selezionato."
        }
        let backtestSignificant = backtest.significance.isSignificant && backtest.strategy.hitRate > backtest.baseline.hitRate
        let foldsPositive = walkForwardFolds.filter { $0.difference > 0 }.count
        let foldsConsistent = !walkForwardFolds.isEmpty && Double(foldsPositive) / Double(walkForwardFolds.count) >= 0.75
        let mlPositive = (mlEvaluation?.auc ?? 0.5) > 0.55

        if backtestSignificant && foldsConsistent && mlPositive {
            return "Il vantaggio osservato supera tutti i controlli su questo campione. Resta un risultato retrospettivo: su un processo casuale non è replicabile in modo sistematico."
        }
        return Disclaimer.noEdge
    }

    var isEdgeDemonstrated: Bool {
        guard let backtest, backtest.drawsEvaluated > 0 else { return false }
        let backtestSignificant = backtest.significance.isSignificant && backtest.strategy.hitRate > backtest.baseline.hitRate
        let foldsPositive = walkForwardFolds.filter { $0.difference > 0 }.count
        let foldsConsistent = !walkForwardFolds.isEmpty && Double(foldsPositive) / Double(walkForwardFolds.count) >= 0.75
        let mlPositive = (mlEvaluation?.auc ?? 0.5) > 0.55
        return backtestSignificant && foldsConsistent && mlPositive
    }

    var checks: [ValidationCheck] {
        var items: [ValidationCheck] = []
        if let backtest {
            let passed = backtest.significance.isSignificant && backtest.strategy.hitRate > backtest.baseline.hitRate
            items.append(ValidationCheck(name: "Backtest walk-forward",
                                         passed: passed,
                                         detail: backtest.significance.interpretation))
        }
        if !walkForwardFolds.isEmpty {
            let positive = walkForwardFolds.filter { $0.difference > 0 }.count
            items.append(ValidationCheck(
                name: "Validazione su \(walkForwardFolds.count) finestre",
                passed: Double(positive) / Double(walkForwardFolds.count) >= 0.75,
                detail: "\(positive) finestre su \(walkForwardFolds.count) superano la baseline casuale."))
        }
        if !monteCarloTests.isEmpty {
            let significant = monteCarloTests.filter(\.isSignificant)
            items.append(ValidationCheck(
                name: "Confronto Monte Carlo",
                passed: !significant.isEmpty,
                detail: significant.isEmpty
                    ? "I dati storici sono compatibili con la casualità su tutti i test eseguiti."
                    : "Test con scostamento: \(significant.map(\.name).joined(separator: ", "))."))
        }
        if let mlEvaluation {
            items.append(ValidationCheck(
                name: "Modello di machine learning",
                passed: mlEvaluation.auc > 0.55,
                detail: "AUC \(String(format: "%.3f", mlEvaluation.auc)) (0,500 = nessuna capacità discriminante)."))
        }
        return items
    }
}

/// Esito di un singolo controllo del sistema di validazione.
struct ValidationCheck: Identifiable, Sendable {
    let name: String
    let passed: Bool
    let detail: String
    var id: String { name }
}

/// **SISTEMA DI VALIDAZIONE**: nessun algoritmo può essere presentato come
/// "migliore" prima di aver superato backtest, walk-forward su più finestre,
/// confronto con baseline casuale, Monte Carlo e test statistici.
enum ValidationEngine {

    static func validate(configuration: BacktestConfiguration,
                         allDraws: [DrawRecord],
                         folds: Int = 4,
                         includeML: Bool = true,
                         progress: (@Sendable (Double) -> Void)? = nil) -> ValidationReport {
        var report = ValidationReport(strategyName: configuration.kind.displayName,
                                      backtest: nil,
                                      walkForwardFolds: [],
                                      monteCarloTests: [],
                                      mlEvaluation: nil)

        progress?(0.05)
        let backtest = BacktestEngine.run(configuration: configuration, allDraws: allDraws) { value in
            progress?(0.05 + value * 0.45)
        }
        report.backtest = backtest

        // Walk-forward su finestre consecutive e non sovrapposte.
        let totalInterval = configuration.endDate.timeIntervalSince(configuration.startDate)
        if totalInterval > 0, folds > 1 {
            let foldInterval = totalInterval / Double(folds)
            for index in 0..<folds {
                var foldConfiguration = configuration
                foldConfiguration.startDate = configuration.startDate.addingTimeInterval(foldInterval * Double(index))
                foldConfiguration.endDate = configuration.startDate.addingTimeInterval(foldInterval * Double(index + 1))
                let foldResult = BacktestEngine.run(configuration: foldConfiguration, allDraws: allDraws)
                guard foldResult.strategy.totalPlays > 0 else { continue }
                report.walkForwardFolds.append(ValidationReport.FoldResult(
                    index: index,
                    start: foldConfiguration.startDate,
                    end: foldConfiguration.endDate,
                    hitRate: foldResult.strategy.hitRate,
                    baselineHitRate: foldResult.baseline.hitRate,
                    plays: foldResult.strategy.totalPlays))
                progress?(0.5 + Double(index + 1) / Double(folds) * 0.25)
            }
        }

        let filter = AnalysisFilter(game: configuration.game,
                                    wheelScope: configuration.wheel.map { WheelScope.single($0) } ?? .all,
                                    period: configuration.lookback,
                                    calendarYear: nil,
                                    cutoffDate: configuration.endDate)
        let context = AnalysisContext(filter: filter, allDraws: allDraws, weights: configuration.weights)
        report.monteCarloTests = MonteCarloEngine.tests(for: context)
        progress?(0.85)

        if includeML {
            let draws = StatisticsEngine.apply(filter, to: allDraws)
            report.mlEvaluation = MLEngine.evaluate(kind: .logisticRegression,
                                                    draws: draws,
                                                    game: configuration.game)
        }
        progress?(1)
        return report
    }
}
