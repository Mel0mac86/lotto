import XCTest
@testable import LottoAIAnalyzer

final class BacktestEngineTests: XCTestCase {

    /// Il controllo più importante dell'app: il backtest non deve mai vedere il futuro.
    func testCutoffExcludesTargetDrawAndFutureDraws() {
        let records = TestSupport.draws(count: 50, startingAt: "2024-01-02")
        let target = records[30]

        var filter = AnalysisFilter(game: .lotto, wheelScope: .single(.bari), period: .all)
        filter.cutoffDate = target.date
        let visible = StatisticsEngine.apply(filter, to: records)

        XCTAssertEqual(visible.count, 30, "Devono essere visibili solo le 30 estrazioni precedenti")
        XCTAssertFalse(visible.contains { $0.date >= target.date })
        XCTAssertFalse(visible.contains { $0.id == target.id })
    }

    /// Le statistiche calcolate con il cutoff coincidono con quelle calcolate
    /// sul solo prefisso storico: nessuna informazione futura filtra nel calcolo.
    func testStatisticsWithCutoffMatchPrefixStatistics() {
        let records = TestSupport.draws(count: 60, startingAt: "2024-01-02")
        let cutoffIndex = 40
        let target = records[cutoffIndex]

        var filter = AnalysisFilter(game: .lotto, wheelScope: .single(.bari), period: .all)
        filter.cutoffDate = target.date
        let context = AnalysisContext(filter: filter, allDraws: records, weights: .balanced)

        let prefix = Array(records[0..<cutoffIndex])
        let expected = StatisticsEngine.computeStatistics(for: prefix, game: .lotto)

        XCTAssertEqual(context.drawCount, cutoffIndex)
        for number in 1...90 {
            XCTAssertEqual(context.statistics.numbers[number]?.occurrences,
                           expected.numbers[number]?.occurrences,
                           "Uscite diverse per il numero \(number)")
            XCTAssertEqual(context.statistics.numbers[number]?.currentDelay,
                           expected.numbers[number]?.currentDelay,
                           "Ritardo diverso per il numero \(number)")
        }
    }

    func testBacktestRunsAndProducesBaseline() {
        let records = TestSupport.draws(count: 260, startingAt: "2022-01-04")
        guard let start = records[dropping: 200]?.date, let end = records.last?.date else {
            return XCTFail("Dati di test insufficienti")
        }

        var configuration = BacktestConfiguration(startDate: start, endDate: end)
        configuration.game = .lotto
        configuration.wheel = .bari
        configuration.kind = .pairs
        configuration.playsPerDraw = 2
        configuration.minimumHistory = 60
        configuration.candidatePoolSize = 20

        let result = BacktestEngine.run(configuration: configuration, allDraws: records)

        XCTAssertGreaterThan(result.drawsEvaluated, 0)
        XCTAssertEqual(result.strategy.totalPlays, result.baseline.totalPlays,
                       "La baseline deve giocare esattamente quanto la strategia")
        XCTAssertEqual(result.strategy.totalCost, result.baseline.totalCost, accuracy: 0.0001)
        XCTAssertEqual(result.strategy.totalPlays, result.drawsEvaluated * configuration.playsPerDraw)
        for step in result.steps {
            XCTAssertEqual(step.plays.count, configuration.playsPerDraw)
            for play in step.plays { XCTAssertEqual(play.count, 2) }
        }
    }

    func testBacktestIsDeterministic() {
        let records = TestSupport.draws(count: 220, startingAt: "2022-01-04")
        guard let start = records[dropping: 180]?.date, let end = records.last?.date else {
            return XCTFail("Dati di test insufficienti")
        }
        var configuration = BacktestConfiguration(startDate: start, endDate: end)
        configuration.kind = .pairs
        configuration.minimumHistory = 60
        configuration.candidatePoolSize = 20

        let first = BacktestEngine.run(configuration: configuration, allDraws: records)
        let second = BacktestEngine.run(configuration: configuration, allDraws: records)

        XCTAssertEqual(first.strategy.winningPlays, second.strategy.winningPlays)
        XCTAssertEqual(first.baseline.winningPlays, second.baseline.winningPlays)
        XCTAssertEqual(first.strategy.totalWinnings, second.strategy.totalWinnings, accuracy: 0.0001)
    }

    func testPayoutTable() {
        let table = PayoutTable.lotto
        XCTAssertEqual(table.payout(matched: 2, stake: 1), 250, accuracy: 0.0001)
        XCTAssertEqual(table.payout(matched: 2, stake: 2), 500, accuracy: 0.0001)
        XCTAssertEqual(table.payout(matched: 0, stake: 5), 0, accuracy: 0.0001)
    }
}

private extension Array {
    /// Elemento in posizione `index`, oppure `nil` se fuori intervallo.
    subscript(dropping index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
