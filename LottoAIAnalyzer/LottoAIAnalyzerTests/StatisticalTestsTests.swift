import XCTest
@testable import LottoAIAnalyzer

final class StatisticalTestsTests: XCTestCase {

    func testChiSquarePValueKnownValues() {
        // Con statistica pari ai gradi di libertà il p-value è vicino a 0,32 per gdl = 1.
        let p = StatisticalTests.chiSquarePValue(statistic: 3.841, degreesOfFreedom: 1)
        XCTAssertEqual(p, 0.05, accuracy: 0.005)

        let p2 = StatisticalTests.chiSquarePValue(statistic: 5.991, degreesOfFreedom: 2)
        XCTAssertEqual(p2, 0.05, accuracy: 0.005)

        let p3 = StatisticalTests.chiSquarePValue(statistic: 16.919, degreesOfFreedom: 9)
        XCTAssertEqual(p3, 0.05, accuracy: 0.005)
    }

    func testStandardNormalCDF() {
        XCTAssertEqual(StatisticalTests.standardNormalCDF(0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StatisticalTests.standardNormalCDF(1.96), 0.975, accuracy: 0.001)
        XCTAssertEqual(StatisticalTests.standardNormalCDF(-1.96), 0.025, accuracy: 0.001)
    }

    func testUniformDataIsNotFlaggedAsSignificant() {
        let observed = Array(repeating: 100.0, count: 90)
        let expected = Array(repeating: 100.0, count: 90)
        let result = StatisticalTests.chiSquareGoodnessOfFit(observed: observed, expected: expected, name: "test")
        XCTAssertFalse(result.isSignificant)
        XCTAssertEqual(result.statistic, 0, accuracy: 0.0001)
    }

    func testStronglySkewedDataIsFlagged() {
        var observed = Array(repeating: 50.0, count: 90)
        observed[0] = 900
        let expected = Array(repeating: 59.44, count: 90)
        let result = StatisticalTests.chiSquareGoodnessOfFit(observed: observed, expected: expected, name: "test")
        XCTAssertTrue(result.isSignificant)
    }

    func testBinomialTestOnFairCoin() {
        let fair = StatisticalTests.binomialTest(successes: 500, trials: 1000, probability: 0.5, name: "moneta")
        XCTAssertFalse(fair.isSignificant)

        let loaded = StatisticalTests.binomialTest(successes: 700, trials: 1000, probability: 0.5, name: "moneta")
        XCTAssertTrue(loaded.isSignificant)
    }

    func testTwoProportionZTestDetectsNoDifference() {
        let result = StatisticalTests.twoProportionZTest(successesA: 100, trialsA: 1000,
                                                         successesB: 102, trialsB: 1000,
                                                         name: "confronto")
        XCTAssertFalse(result.isSignificant)
        XCTAssertTrue(result.interpretation.contains(Disclaimer.noEdge))
    }

    func testTwoProportionZTestDetectsRealDifference() {
        let result = StatisticalTests.twoProportionZTest(successesA: 300, trialsA: 1000,
                                                         successesB: 100, trialsB: 1000,
                                                         name: "confronto")
        XCTAssertTrue(result.isSignificant)
    }
}

final class MonteCarloEngineTests: XCTestCase {

    func testSimulationProducesUniformFrequencies() {
        let context = TestSupport.context(TestSupport.draws(count: 100))
        let result = MonteCarloEngine.run(context: context, iterations: 20_000, seed: 4242)

        let frequencies = (1...90).map { result.simulatedFrequency[$0] ?? 0 }
        let expected = 5.0 / 90.0
        for frequency in frequencies {
            XCTAssertEqual(frequency, expected, accuracy: 0.01,
                           "La simulazione casuale deve dare frequenze vicine a k/90")
        }
        XCTAssertEqual(frequencies.reduce(0, +), 5.0, accuracy: 0.01)
    }

    func testSimulationIsDeterministicWithSameSeed() {
        let context = TestSupport.context(TestSupport.draws(count: 60))
        let first = MonteCarloEngine.run(context: context, iterations: 5_000, seed: 7)
        let second = MonteCarloEngine.run(context: context, iterations: 5_000, seed: 7)
        XCTAssertEqual(first.simulatedFrequency[42], second.simulatedFrequency[42])
        XCTAssertEqual(first.simulatedSums, second.simulatedSums)
    }

    func testRandomHistoryPassesRandomnessTests() {
        // Uno storico generato in modo uniforme non deve risultare "non casuale".
        let context = TestSupport.context(TestSupport.draws(count: 2000, seed: 31337))
        let tests = MonteCarloEngine.tests(for: context)
        // Cinque test al 5%: l'atteso è 0,25 falsi positivi. Su dodici semi diversi il
        // massimo osservato è 1; la soglia 2 lascia margine senza rendere il test inutile.
        let significant = tests.filter(\.isSignificant)
        XCTAssertLessThanOrEqual(significant.count, 2,
                                 "Uno storico uniforme non deve risultare sistematicamente non casuale")
    }
}

final class SeededRandomTests: XCTestCase {

    func testSameSeedProducesSameSequence() {
        var first = SeededRandom(seed: 2024)
        var second = SeededRandom(seed: 2024)
        for _ in 0..<50 {
            XCTAssertEqual(first.next(), second.next())
        }
    }

    func testNextUnitIsInRange() {
        var generator = SeededRandom(seed: 5)
        for _ in 0..<1000 {
            let value = generator.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testWeightedSampleReturnsDistinctIndices() {
        var generator = SeededRandom(seed: 9)
        let weights = (1...90).map { Double($0) }
        let picked = generator.weightedSample(weights: weights, count: 6)
        XCTAssertEqual(picked.count, 6)
        XCTAssertEqual(Set(picked).count, 6)
    }

    func testZeroWeightsAreNeverPicked() {
        var generator = SeededRandom(seed: 3)
        var weights = [Double](repeating: 0, count: 10)
        weights[4] = 1
        weights[8] = 1
        let picked = generator.weightedSample(weights: weights, count: 5)
        XCTAssertEqual(Set(picked), [4, 8])
    }
}

final class MLEngineTests: XCTestCase {

    func testAUCIsHalfForRandomPredictions() {
        var generator = SeededRandom(seed: 1)
        var probabilities: [Double] = []
        var labels: [Int] = []
        for _ in 0..<4000 {
            probabilities.append(generator.nextUnit())
            labels.append(generator.nextUnit() < 0.06 ? 1 : 0)
        }
        let auc = MLEngine.areaUnderROC(probabilities: probabilities, labels: labels)
        XCTAssertEqual(auc, 0.5, accuracy: 0.06)
    }

    func testAUCIsOneForPerfectSeparation() {
        let probabilities = [0.1, 0.2, 0.3, 0.8, 0.9]
        let labels = [0, 0, 0, 1, 1]
        XCTAssertEqual(MLEngine.areaUnderROC(probabilities: probabilities, labels: labels), 1.0, accuracy: 0.0001)
    }

    func testLogLossOfPerfectPredictionIsZero() {
        let loss = MLEngine.logLoss(probabilities: [1, 0, 1], labels: [1, 0, 1])
        XCTAssertEqual(loss, 0, accuracy: 0.0001)
    }

    func testLogisticRegressionLearnsSeparableData() {
        var features: [[Double]] = []
        var labels: [Int] = []
        for value in stride(from: -2.0, through: 2.0, by: 0.05) {
            features.append([value])
            labels.append(value > 0 ? 1 : 0)
        }
        var model = LogisticRegression(featureCount: 1)
        model.train(features: features, labels: labels, epochs: 600, learningRate: 0.5)

        let positive = model.predictProbability([2.0])
        let negative = model.predictProbability([-2.0])
        XCTAssertGreaterThan(positive, 0.5, "Il lato positivo deve essere classificato come tale")
        XCTAssertLessThan(negative, 0.5, "Il lato negativo deve essere classificato come tale")
        XCTAssertGreaterThan(positive - negative, 0.2, "Il modello deve separare le due classi")
    }

    func testKMeansSeparatesTwoClusters() {
        let points = [[0.0, 0.0], [0.1, 0.1], [0.05, 0.0],
                      [5.0, 5.0], [5.1, 4.9], [4.9, 5.1]]
        let result = KMeans.fit(points: points, clusters: 2, seed: 3)
        XCTAssertEqual(result.assignments[0], result.assignments[1])
        XCTAssertEqual(result.assignments[3], result.assignments[4])
        XCTAssertNotEqual(result.assignments[0], result.assignments[3])
    }

    func testBayesianPosteriorStaysCloseToTheoreticalValue() {
        let context = TestSupport.context(TestSupport.draws(count: 1500, seed: 777))
        let posteriors = BayesianModel().posteriors(context: context)

        XCTAssertEqual(posteriors.count, 90)
        for posterior in posteriors {
            XCTAssertEqual(posterior.mean, 5.0 / 90.0, accuracy: 0.02)
        }
        let outside = posteriors.filter { !$0.containsTheoretical }
        XCTAssertLessThanOrEqual(outside.count, 12,
                                 "Su dati uniformi pochi numeri devono uscire dall'intervallo al 95%")
    }

    func testAnomalyDetectionReturnsRankedResults() {
        let context = TestSupport.context(TestSupport.draws(count: 300))
        let anomalies = MLEngine.anomalies(context: context, limit: 5)
        XCTAssertEqual(anomalies.count, 5)
        for index in 1..<anomalies.count {
            XCTAssertGreaterThanOrEqual(anomalies[index - 1].distance, anomalies[index].distance)
        }
    }
}

final class PatternFinderTests: XCTestCase {

    func testInsufficientDataIsReported() {
        let context = TestSupport.context(TestSupport.draws(count: 5))
        let patterns = PatternFinder.analyze(context: context)
        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns.first?.title, "Dati insufficienti")
    }

    func testRandomHistoryProducesFewNoteworthyPatterns() {
        let context = TestSupport.context(TestSupport.draws(count: 1200, seed: 555))
        let patterns = PatternFinder.analyze(context: context)

        XCTAssertFalse(patterns.isEmpty)
        XCTAssertTrue(patterns.contains { $0.title == "Nota sulla molteplicità dei test" })
        let noteworthy = patterns.filter(\.isNoteworthy)
        XCTAssertLessThanOrEqual(noteworthy.count, 3,
                                 "Su dati casuali la maggior parte dei pattern deve risultare compatibile con il caso")
    }

    func testEveryPatternHasAnAssessment() {
        let context = TestSupport.context(TestSupport.draws(count: 400))
        for pattern in PatternFinder.analyze(context: context) {
            XCTAssertFalse(pattern.assessment.isEmpty, "Pattern senza valutazione: \(pattern.title)")
        }
    }
}

final class DisclaimerTests: XCTestCase {

    /// Nessun testo dell'app deve promettere previsioni.
    func testExplanationsNeverClaimPrediction() {
        let context = TestSupport.context(TestSupport.draws(count: 300))
        let combination = CombinationEngine.evaluate([7, 22, 38, 55, 79], context: context)
        let text = (combination.reasons + AIExplainer.explain(combination: combination, context: context).map(\.body))
            .joined(separator: " ")
            .lowercased()

        for forbidden in ["uscirà", "sicuramente vincente", "previsione certa", "garantit"] {
            XCTAssertFalse(text.contains(forbidden), "Testo con promessa di previsione: «\(forbidden)»")
        }
        XCTAssertTrue(combination.reasons.contains(Disclaimer.explainer))
    }

    func testEmptyContextDoesNotCrash() {
        let context = TestSupport.context([])
        XCTAssertTrue(context.isEmpty)
        XCTAssertTrue(PairGenerator.topPairs(context: context, limit: 5).isEmpty)
        XCTAssertTrue(TripleGenerator.topTriples(context: context, limit: 5).isEmpty)
        XCTAssertTrue(QuintupleGenerator.generate(
            QuintupleGenerator.Request(context: context, count: 3)).isEmpty)
    }
}
