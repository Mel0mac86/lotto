import XCTest
@testable import LottoAIAnalyzer

final class ScoringEngineTests: XCTestCase {

    func testScoresStayWithinBounds() {
        let records = TestSupport.draws(count: 300)
        let stats = StatisticsEngine.computeStatistics(for: records, game: .lotto)
        let scores = ScoringEngine.score(statistics: stats, weights: .balanced)

        XCTAssertEqual(scores.count, 90)
        for score in scores.values {
            XCTAssertGreaterThanOrEqual(score.score, 0)
            XCTAssertLessThanOrEqual(score.score, 100)
            for component in score.components.labelledValues {
                XCTAssertGreaterThanOrEqual(component.1, 0)
                XCTAssertLessThanOrEqual(component.1, 100)
            }
        }
    }

    func testPercentileRanksHandleTies() {
        let ranks = ScoringEngine.percentileRanks([5, 5, 5, 5])
        XCTAssertEqual(Set(ranks).count, 1, "Valori identici devono ricevere lo stesso percentile")

        let ordered = ScoringEngine.percentileRanks([1, 2, 3, 4, 5])
        XCTAssertEqual(ordered.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(ordered.last ?? -1, 100, accuracy: 0.0001)
    }

    func testTrendScoreIsNeutralAtOne() {
        XCTAssertEqual(ScoringEngine.trendScore(1.0), 50, accuracy: 0.0001)
        XCTAssertGreaterThan(ScoringEngine.trendScore(1.5), 50)
        XCTAssertLessThan(ScoringEngine.trendScore(0.5), 50)
    }

    func testDelayWeightRewardsOverdueNumbers() {
        // Il 90 non esce mai: con pesi orientati al ritardo deve avere l'indice più alto.
        var combinations: [[Int]] = []
        for index in 0..<60 {
            let base = (index % 17) * 5 + 1
            combinations.append([base, base + 1, base + 2, base + 3, base + 4].map { min($0, 89) })
        }
        let records = TestSupport.draws(combinations)
        let stats = StatisticsEngine.computeStatistics(for: records, game: .lotto)
        let scores = ScoringEngine.score(statistics: stats, weights: .delayFocused)

        let ranked = ScoringEngine.ranked(scores)
        XCTAssertEqual(stats.numbers[90]?.occurrences, 0)
        XCTAssertTrue(ranked.prefix(5).contains { $0.number == 90 })
    }

    func testWeightsNormalization() {
        let weights = ScoringWeights(frequency: 2, recency: 2, delay: 2, trend: 2, coOccurrence: 1, stability: 1)
        let normalized = weights.normalized()
        XCTAssertEqual(normalized.total, 1.0, accuracy: 0.0001)
    }

    func testScoreBands() {
        XCTAssertEqual(ScoreBand(score: 95), .high)
        XCTAssertEqual(ScoreBand(score: 60), .medium)
        XCTAssertEqual(ScoreBand(score: 10), .low)
    }
}

final class CoOccurrenceMatrixTests: XCTestCase {

    func testIndexPairRoundTrip() {
        for a in 1...89 {
            for b in (a + 1)...90 {
                let index = CoOccurrenceMatrix.index(a, b)
                let pair = CoOccurrenceMatrix.pair(at: index)
                XCTAssertEqual(pair.0, a)
                XCTAssertEqual(pair.1, b)
            }
        }
    }

    func testIndicesAreUniqueAndInRange() {
        var seen = Set<Int>()
        for a in 1...89 {
            for b in (a + 1)...90 {
                let index = CoOccurrenceMatrix.index(a, b)
                XCTAssertTrue((0..<CoOccurrenceMatrix.pairCount).contains(index))
                XCTAssertTrue(seen.insert(index).inserted, "Indice duplicato per \(a)-\(b)")
            }
        }
        XCTAssertEqual(seen.count, CoOccurrenceMatrix.pairCount)
    }

    func testSymmetryAndCounts() {
        let records = TestSupport.draws([[1, 2, 3, 4, 5],
                                         [1, 2, 10, 11, 12],
                                         [1, 3, 20, 21, 22]])
        let matrix = CoOccurrenceMatrix.build(from: records, drawnPerDraw: 5)
        XCTAssertEqual(matrix.count(1, 2), 2)
        XCTAssertEqual(matrix.count(2, 1), 2)
        XCTAssertEqual(matrix.count(1, 3), 2)
        XCTAssertEqual(matrix.count(4, 5), 1)
        XCTAssertEqual(matrix.count(4, 4), 0)
    }

    func testExpectedPairCountMatchesCombinatorics() {
        var matrix = CoOccurrenceMatrix(drawCount: 0, drawnPerDraw: 5)
        for _ in 0..<8010 { matrix.add([1, 2, 3, 4, 5]) }
        // P(coppia specifica) = C(5,2)/C(90,2) = 10/4005
        XCTAssertEqual(matrix.expectedPairCount, 8010 * 10.0 / 4005.0, accuracy: 0.001)
    }
}

final class SetOccurrenceIndexTests: XCTestCase {

    func testPairAndTripleCounts() {
        let records = TestSupport.draws([[1, 2, 3, 4, 5],
                                         [1, 2, 3, 10, 11],
                                         [1, 2, 20, 21, 22]])
        let index = SetOccurrenceIndex(draws: records, drawnPerDraw: 5)

        XCTAssertEqual(index.pairCount(1, 2), 3)
        XCTAssertEqual(index.tripleCount(1, 2, 3), 2)
        XCTAssertEqual(index.tripleCount(3, 2, 1), 2, "L'ordine dei numeri non deve contare")
        XCTAssertEqual(index.tripleCount(1, 2, 99), 0)
    }

    func testDelays() {
        let records = TestSupport.draws([[1, 2, 3, 4, 5],
                                         [10, 11, 12, 13, 14],
                                         [20, 21, 22, 23, 24]])
        let index = SetOccurrenceIndex(draws: records, drawnPerDraw: 5)
        XCTAssertEqual(index.pairDelay(1, 2), 2)
        XCTAssertEqual(index.pairDelay(20, 21), 0)
        XCTAssertEqual(index.pairDelay(1, 90), 3, "Una coppia mai uscita ha ritardo pari al numero di estrazioni")
    }
}
