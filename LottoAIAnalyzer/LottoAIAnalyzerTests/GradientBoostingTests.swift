import XCTest
@testable import LottoAIAnalyzer

final class GradientBoostingTests: XCTestCase {

    /// Il modello deve trovare un segnale quando il segnale c'è davvero:
    /// senza questa verifica, un'AUC vicina a 0,5 sui dati del Lotto non
    /// direbbe nulla — potrebbe essere il modello a non funzionare.
    func testLearnsARealSignal() {
        var generator = SeededRandom(seed: 1)
        var features: [[Double]] = []
        var labels: [Int] = []
        for _ in 0..<2400 {
            let row = (0..<6).map { _ in generator.nextUnit() }
            features.append(row)
            labels.append(row[0] + row[1] > 1.1 ? 1 : 0)
        }
        let split = 1700
        let model = GradientBoostingClassifier(treeCount: 40, maxDepth: 3, learningRate: 0.15)
        model.train(features: Array(features[0..<split]), labels: Array(labels[0..<split]))

        let probabilities = features[split...].map { model.predictProbability($0) }
        let auc = MLEngine.areaUnderROC(probabilities: probabilities, labels: Array(labels[split...]))
        XCTAssertGreaterThan(auc, 0.90, "Su una regola deterministica il modello deve separare le classi")
        XCTAssertGreaterThan(model.trainedTreeCount, 0)
    }

    /// Il controllo speculare: su etichette casuali con lo stesso sbilanciamento
    /// del problema reale (5 numeri su 90) l'AUC deve restare attorno a 0,5.
    /// È il risultato che l'app riporta invece di nasconderlo.
    func testReportsNoSignalOnRandomLabels() {
        var generator = SeededRandom(seed: 2)
        var features: [[Double]] = []
        var labels: [Int] = []
        for _ in 0..<4000 {
            features.append((0..<6).map { _ in generator.nextUnit() })
            labels.append(generator.nextUnit() < 5.0 / 90.0 ? 1 : 0)
        }
        let split = 2800
        let model = GradientBoostingClassifier(treeCount: 40, maxDepth: 3, learningRate: 0.15)
        model.train(features: Array(features[0..<split]), labels: Array(labels[0..<split]))

        let probabilities = features[split...].map { model.predictProbability($0) }
        let auc = MLEngine.areaUnderROC(probabilities: probabilities, labels: Array(labels[split...]))
        XCTAssertEqual(auc, 0.5, accuracy: 0.08,
                       "Senza segnale il modello non deve produrre capacità discriminante")
    }

    func testProbabilitiesStayInRange() {
        var generator = SeededRandom(seed: 3)
        var features: [[Double]] = []
        var labels: [Int] = []
        for _ in 0..<800 {
            features.append((0..<6).map { _ in generator.nextUnit() })
            labels.append(generator.nextUnit() < 0.2 ? 1 : 0)
        }
        let model = GradientBoostingClassifier(treeCount: 25, maxDepth: 3)
        model.train(features: features, labels: labels)

        for feature in features.prefix(100) {
            let probability = model.predictProbability(feature)
            XCTAssertGreaterThanOrEqual(probability, 0)
            XCTAssertLessThanOrEqual(probability, 1)
        }
    }

    func testIsDeterministicWithSameSeed() {
        var generator = SeededRandom(seed: 4)
        var features: [[Double]] = []
        var labels: [Int] = []
        for _ in 0..<600 {
            features.append((0..<6).map { _ in generator.nextUnit() })
            labels.append(generator.nextUnit() < 0.3 ? 1 : 0)
        }
        func probability() -> Double {
            let model = GradientBoostingClassifier(treeCount: 15, maxDepth: 3)
            model.train(features: features, labels: labels, seed: 99)
            return model.predictProbability(features[0])
        }
        XCTAssertEqual(probability(), probability(), accuracy: 1e-12)
    }

    func testRegressionTreeLeafUsesNewtonStep() {
        // Con gradienti costanti pari a g e hessiane pari a h, la foglia vale
        // n·g / (n·h + λ); con λ = 1, g = 0,5, h = 0,25 e n = 100 → 50 / 26.
        let features = (0..<100).map { [Double($0)] }
        let gradients = [Double](repeating: 0.5, count: 100)
        let hessians = [Double](repeating: 0.25, count: 100)
        let tree = RegressionTree(maxDepth: 0, minSamples: 20, lambda: 1)
        tree.train(features: features, gradients: gradients, hessians: hessians)
        XCTAssertEqual(tree.predict([0]), 50.0 / 26.0, accuracy: 1e-9)
    }
}
