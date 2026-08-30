import XCTest
@testable import LottoAIAnalyzer

final class StatisticsEngineTests: XCTestCase {

    func testOccurrencesAndFrequency() {
        let records = TestSupport.draws([[1, 2, 3, 4, 5],
                                         [1, 2, 6, 7, 8],
                                         [1, 9, 10, 11, 12]])
        let stats = StatisticsEngine.computeStatistics(for: records, game: .lotto)

        XCTAssertEqual(stats.drawCount, 3)
        XCTAssertEqual(stats.numbers[1]?.occurrences, 3)
        XCTAssertEqual(stats.numbers[2]?.occurrences, 2)
        XCTAssertEqual(stats.numbers[90]?.occurrences, 0)
        XCTAssertEqual(stats.numbers[1]?.frequency ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(stats.numbers[2]?.frequency ?? 0, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testCurrentDelay() {
        let records = TestSupport.draws([[1, 2, 3, 4, 5],
                                         [6, 7, 8, 9, 10],
                                         [11, 12, 13, 14, 15]])
        let stats = StatisticsEngine.computeStatistics(for: records, game: .lotto)

        // Il 13 è uscito nell'ultima estrazione.
        XCTAssertEqual(stats.numbers[13]?.currentDelay, 0)
        // Il 7 è uscito nella penultima.
        XCTAssertEqual(stats.numbers[7]?.currentDelay, 1)
        // L'1 è uscito nella prima delle tre.
        XCTAssertEqual(stats.numbers[1]?.currentDelay, 2)
        // Un numero mai uscito ha ritardo pari all'intera finestra.
        XCTAssertEqual(stats.numbers[90]?.currentDelay, 3)
    }

    func testMaxDelayIncludesCurrentDelay() {
        // Il 5 esce solo nella prima estrazione: il ritardo corrente è 3.
        let records = TestSupport.draws([[5, 1, 2, 3, 4],
                                         [10, 11, 12, 13, 14],
                                         [20, 21, 22, 23, 24],
                                         [30, 31, 32, 33, 34]])
        let stats = StatisticsEngine.computeStatistics(for: records, game: .lotto)
        XCTAssertEqual(stats.numbers[5]?.currentDelay, 3)
        XCTAssertEqual(stats.numbers[5]?.maxDelay, 3)
        XCTAssertEqual(stats.numbers[5]?.delayRatio ?? 0, 1.0, accuracy: 0.0001)
    }

    func testDistributions() {
        let records = TestSupport.draws([[2, 4, 6, 8, 10],     // 5 pari, 5 bassi
                                         [81, 83, 85, 87, 89]]) // 5 dispari, 5 alti
        let stats = StatisticsEngine.computeStatistics(for: records, game: .lotto)

        XCTAssertEqual(stats.evenDistribution[5], 1)
        XCTAssertEqual(stats.evenDistribution[0], 1)
        XCTAssertEqual(stats.lowDistribution[5], 1)
        XCTAssertEqual(stats.lowDistribution[0], 1)
        XCTAssertEqual(stats.sums.sorted(), [30, 425])
        XCTAssertEqual(stats.decadeDistribution[0], 5)
        XCTAssertEqual(stats.decadeDistribution[8], 5)
    }

    func testConsecutiveDetection() {
        let records = TestSupport.draws([[1, 2, 40, 60, 80],
                                         [5, 20, 35, 50, 70]])
        let stats = StatisticsEngine.computeStatistics(for: records, game: .lotto)
        XCTAssertEqual(stats.drawsWithConsecutives, 1)
    }

    func testPeriodFilterExcludesOlderDraws() {
        let old = DrawRecord(date: TestSupport.date("2015-01-05"), game: .lotto, wheel: .bari,
                             numbers: [1, 2, 3, 4, 5])
        let recent = DrawRecord(date: Date(), game: .lotto, wheel: .bari, numbers: [6, 7, 8, 9, 10])
        let filter = AnalysisFilter(game: .lotto, wheelScope: .single(.bari), period: .oneYear)
        let filtered = StatisticsEngine.apply(filter, to: [old, recent])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.numbers, [6, 7, 8, 9, 10])
    }

    func testWheelFilter() {
        let bari = DrawRecord(date: TestSupport.date("2024-01-02"), game: .lotto, wheel: .bari,
                              numbers: [1, 2, 3, 4, 5])
        let roma = DrawRecord(date: TestSupport.date("2024-01-02"), game: .lotto, wheel: .roma,
                              numbers: [6, 7, 8, 9, 10])
        let filter = AnalysisFilter(game: .lotto, wheelScope: .single(.roma), period: .all)
        let filtered = StatisticsEngine.apply(filter, to: [bari, roma])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.wheel, .roma)
    }
}
