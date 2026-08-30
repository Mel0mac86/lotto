import XCTest
@testable import LottoAIAnalyzer

final class GeneratorTests: XCTestCase {

    func testPairGeneratorReturnsSortedDistinctPairs() {
        let context = TestSupport.context(TestSupport.draws(count: 200))
        let pairs = PairGenerator.topPairs(context: context, limit: 10)

        XCTAssertEqual(pairs.count, 10)
        for pair in pairs {
            XCTAssertLessThan(pair.first, pair.second)
            XCTAssertTrue((1...90).contains(pair.first))
            XCTAssertTrue((1...90).contains(pair.second))
            XCTAssertFalse(pair.reasons.isEmpty)
        }
        XCTAssertEqual(Set(pairs.map(\.id)).count, pairs.count)
        // Ordinamento decrescente per indice.
        for index in 1..<pairs.count {
            XCTAssertGreaterThanOrEqual(pairs[index - 1].score, pairs[index].score)
        }
    }

    func testPairGeneratorRespectsPool() {
        let context = TestSupport.context(TestSupport.draws(count: 150))
        let pool: Set<Int> = [3, 7, 11, 19, 23]
        let pairs = PairGenerator.topPairs(context: context, limit: 5, restrictedTo: pool)

        for pair in pairs {
            XCTAssertTrue(pool.contains(pair.first))
            XCTAssertTrue(pool.contains(pair.second))
        }
    }

    func testTripleGeneratorProducesThreeDistinctNumbers() {
        let context = TestSupport.context(TestSupport.draws(count: 200))
        let triples = TripleGenerator.topTriples(context: context, limit: 8, poolSize: 25)

        XCTAssertEqual(triples.count, 8)
        for triple in triples {
            XCTAssertEqual(triple.numbers.count, 3)
            XCTAssertEqual(Set(triple.numbers).count, 3)
            XCTAssertEqual(triple.numbers, triple.numbers.sorted())
        }
        XCTAssertEqual(Set(triples.map(\.id)).count, triples.count)
    }

    func testQuintupleGeneratorRespectsSizeAndUniqueness() {
        let context = TestSupport.context(TestSupport.draws(count: 250))
        let request = QuintupleGenerator.Request(context: context,
                                                 mode: .balanced,
                                                 count: 5,
                                                 seed: 12345,
                                                 candidateSamples: 800)
        let combinations = QuintupleGenerator.generate(request)

        XCTAssertEqual(combinations.count, 5)
        for combination in combinations {
            XCTAssertEqual(combination.numbers.count, 5)
            XCTAssertEqual(Set(combination.numbers).count, 5)
            XCTAssertEqual(combination.numbers, combination.numbers.sorted())
            XCTAssertTrue(combination.numbers.allSatisfy { (1...90).contains($0) })
            XCTAssertGreaterThanOrEqual(combination.score, 0)
            XCTAssertLessThanOrEqual(combination.score, 100)
        }
        XCTAssertEqual(Set(combinations.map(\.id)).count, combinations.count,
                       "Le combinazioni generate devono essere distinte")
    }

    func testQuintupleGeneratorIsDeterministicWithSameSeed() {
        let context = TestSupport.context(TestSupport.draws(count: 200))
        func generate() -> [[Int]] {
            QuintupleGenerator.generate(QuintupleGenerator.Request(context: context,
                                                                  mode: .conservative,
                                                                  count: 3,
                                                                  seed: 777,
                                                                  candidateSamples: 600)).map(\.numbers)
        }
        XCTAssertEqual(generate(), generate())
    }

    func testSuperenalottoGeneratesSixNumbers() {
        let records = TestSupport.draws(count: 200, game: .superenalotto, wheel: nil)
        let context = TestSupport.context(records, game: .superenalotto, wheel: nil)
        let combinations = QuintupleGenerator.generate(
            QuintupleGenerator.Request(context: context, mode: .balanced, count: 2,
                                       seed: 4242, candidateSamples: 800))

        XCTAssertFalse(combinations.isEmpty)
        for combination in combinations {
            XCTAssertEqual(combination.numbers.count, 6)
        }
    }

    func testConstraintsAcceptTypicalCombinations() {
        let context = TestSupport.context(TestSupport.draws(count: 300))
        let constraints = CombinationConstraints.derived(from: context, size: 5)
        // Combinazione ben distribuita.
        XCTAssertTrue(constraints.isSatisfied(by: [7, 22, 38, 55, 79]))
        // Cinque numeri consecutivi: pattern estremo, deve essere rifiutato.
        XCTAssertFalse(constraints.isSatisfied(by: [1, 2, 3, 4, 5]))
    }

    func testTopKBufferKeepsBestElements() {
        var buffer = TopKBuffer<Int>(capacity: 3) { $0 > $1 }
        for value in [5, 1, 9, 3, 7, 2, 8] { buffer.insert(value) }
        XCTAssertEqual(buffer.sortedElements(), [9, 8, 7])
    }

    func testCombinationBalanceScoreRange() {
        let context = TestSupport.context(TestSupport.draws(count: 200))
        for numbers in [[1, 2, 3, 4, 5], [7, 22, 38, 55, 79], [86, 87, 88, 89, 90]] {
            let score = CombinationEngine.balanceScore(numbers, context: context)
            XCTAssertGreaterThanOrEqual(score, 0)
            XCTAssertLessThanOrEqual(score, 100)
        }
        // Una combinazione equilibrata deve superare quella tutta concentrata in fondo.
        let balanced = CombinationEngine.balanceScore([7, 22, 38, 55, 79], context: context)
        let skewed = CombinationEngine.balanceScore([86, 87, 88, 89, 90], context: context)
        XCTAssertGreaterThan(balanced, skewed)
    }
}

final class MultiWheelEngineTests: XCTestCase {

    func testBuildsContextsForWheelsWithData() {
        var records = TestSupport.draws(count: 80, wheel: .bari, seed: 1)
        records += TestSupport.draws(count: 80, wheel: .roma, seed: 2)
        let filter = AnalysisFilter(game: .lotto, wheelScope: .all, period: .all)
        let contexts = MultiWheelEngine.buildContexts(filter: filter, allDraws: records, weights: .balanced)

        XCTAssertEqual(contexts.contexts.count, 2)
        XCTAssertEqual(Set(contexts.wheels), [.bari, .roma])
    }

    func testMultiWheelNumbersAreScoredAndBounded() {
        var records = TestSupport.draws(count: 120, wheel: .bari, seed: 11)
        records += TestSupport.draws(count: 120, wheel: .roma, seed: 12)
        records += TestSupport.draws(count: 120, wheel: .milano, seed: 13)
        let filter = AnalysisFilter(game: .lotto, wheelScope: .all, period: .all)
        let contexts = MultiWheelEngine.buildContexts(filter: filter, allDraws: records, weights: .balanced)
        let numbers = MultiWheelEngine.numbers(from: contexts, scoreThreshold: 60, limit: 20)

        XCTAssertFalse(numbers.isEmpty)
        for item in numbers {
            XCTAssertFalse(item.wheels.isEmpty)
            XCTAssertGreaterThanOrEqual(item.score, 0)
            XCTAssertLessThanOrEqual(item.score, 100)
        }
    }

    func testMultiWheelPairsReportInvolvedWheels() {
        var records = TestSupport.draws(count: 100, wheel: .bari, seed: 21)
        records += TestSupport.draws(count: 100, wheel: .napoli, seed: 22)
        let filter = AnalysisFilter(game: .lotto, wheelScope: .all, period: .all)
        let contexts = MultiWheelEngine.buildContexts(filter: filter, allDraws: records, weights: .balanced)
        let pairs = MultiWheelEngine.pairs(from: contexts, limit: 5)

        XCTAssertFalse(pairs.isEmpty)
        for pair in pairs {
            XCTAssertEqual(pair.numbers.count, 2)
            XCTAssertGreaterThan(pair.wheelCount, 0)
            XCTAssertFalse(pair.reasons.isEmpty)
        }
    }
}
