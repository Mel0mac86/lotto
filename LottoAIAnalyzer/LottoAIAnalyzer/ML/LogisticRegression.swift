import Foundation

/// Regressione logistica addestrata con discesa del gradiente.
///
/// Nel contesto dell'app serve a **misurare** quanto le feature storiche siano
/// informative rispetto all'esito di un'estrazione: il risultato atteso su dati
/// realmente casuali è un'accuratezza indistinguibile dalla baseline.
struct LogisticRegression: Sendable {
    private(set) var weights: [Double]
    private(set) var bias: Double

    init(featureCount: Int) {
        weights = Array(repeating: 0, count: featureCount)
        bias = 0
    }

    mutating func train(features: [[Double]],
                        labels: [Int],
                        epochs: Int = 120,
                        learningRate: Double = 0.15,
                        l2: Double = 0.001) {
        guard !features.isEmpty, features.count == labels.count else { return }
        let sampleCount = Double(features.count)

        for _ in 0..<epochs {
            var weightGradients = [Double](repeating: 0, count: weights.count)
            var biasGradient = 0.0

            for (index, feature) in features.enumerated() {
                let prediction = predictProbability(feature)
                let error = prediction - Double(labels[index])
                for dimension in 0..<weights.count where dimension < feature.count {
                    weightGradients[dimension] += error * feature[dimension]
                }
                biasGradient += error
            }

            for dimension in 0..<weights.count {
                let gradient = weightGradients[dimension] / sampleCount + l2 * weights[dimension]
                weights[dimension] -= learningRate * gradient
            }
            bias -= learningRate * biasGradient / sampleCount
        }
    }

    func predictProbability(_ feature: [Double]) -> Double {
        var z = bias
        for index in 0..<Swift.min(weights.count, feature.count) {
            z += weights[index] * feature[index]
        }
        return 1 / (1 + exp(-z))
    }

    func predict(_ feature: [Double], threshold: Double = 0.5) -> Int {
        predictProbability(feature) >= threshold ? 1 : 0
    }

    /// Peso appreso per ciascuna feature: il segno indica la direzione dell'effetto,
    /// il valore assoluto quanto la feature pesa nel modello.
    func featureImportance(names: [String]) -> [(name: String, weight: Double)] {
        zip(names, weights).map { ($0, $1) }
    }
}
