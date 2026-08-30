import Foundation

/// Albero di regressione a errore quadratico, usato come learner di base del
/// gradient boosting.
///
/// A differenza di `DecisionTree` (classificazione, criterio di Gini) qui le foglie
/// contengono un valore continuo: il passo di Newton di Friedman
/// `somma(gradienti) / (somma(hessiane) + λ)`, che è la stessa formula usata dalle
/// implementazioni della famiglia XGBoost/LightGBM.
final class RegressionTree: @unchecked Sendable {

    private indirect enum Node {
        case leaf(value: Double)
        case split(feature: Int, threshold: Double, left: Node, right: Node)
    }

    private var root: Node = .leaf(value: 0)
    private let maxDepth: Int
    private let minSamples: Int
    /// Regolarizzazione L2 sui valori delle foglie.
    private let lambda: Double

    init(maxDepth: Int = 3, minSamples: Int = 20, lambda: Double = 1.0) {
        self.maxDepth = maxDepth
        self.minSamples = minSamples
        self.lambda = lambda
    }

    /// - Parameters:
    ///   - gradients: derivate prime della perdita rispetto al punteggio corrente.
    ///   - hessians: derivate seconde; per la perdita logistica `p * (1 - p)`.
    ///   - featureSubset: colonne candidate (per il campionamento delle feature).
    func train(features: [[Double]],
               gradients: [Double],
               hessians: [Double],
               featureSubset: [Int]? = nil) {
        guard !features.isEmpty else { return }
        root = build(indices: Array(features.indices),
                     features: features,
                     gradients: gradients,
                     hessians: hessians,
                     featureSubset: featureSubset ?? Array(0..<(features[0].count)),
                     depth: 0)
    }

    func predict(_ feature: [Double]) -> Double {
        var node = root
        while true {
            switch node {
            case .leaf(let value):
                return value
            case .split(let index, let threshold, let left, let right):
                node = (index < feature.count && feature[index] <= threshold) ? left : right
            }
        }
    }

    // MARK: - Costruzione

    private func build(indices: [Int],
                       features: [[Double]],
                       gradients: [Double],
                       hessians: [Double],
                       featureSubset: [Int],
                       depth: Int) -> Node {
        let leafValue = self.leafValue(indices, gradients: gradients, hessians: hessians)
        guard depth < maxDepth, indices.count >= minSamples * 2 else {
            return .leaf(value: leafValue)
        }

        let parentGain = gain(indices, gradients: gradients, hessians: hessians)
        var best: (feature: Int, threshold: Double, improvement: Double, left: [Int], right: [Int])?

        for feature in featureSubset {
            // Quantili stimati su un campione: ordinare tutti i valori a ogni nodo
            // domina il costo dell'addestramento senza migliorare le soglie.
            let step = max(1, indices.count / 512)
            var values: [Double] = []
            values.reserveCapacity(indices.count / step + 1)
            var position = 0
            while position < indices.count {
                values.append(features[indices[position]][feature])
                position += step
            }
            values.sort()
            guard let minimum = values.first, let maximum = values.last, maximum > minimum else { continue }
            let thresholds = Set([0.2, 0.4, 0.6, 0.8].map { values[Int(Double(values.count - 1) * $0)] })
            for threshold in thresholds where threshold < maximum {
                var left: [Int] = [], right: [Int] = []
                for index in indices {
                    if features[index][feature] <= threshold { left.append(index) } else { right.append(index) }
                }
                guard left.count >= minSamples, right.count >= minSamples else { continue }
                let improvement = gain(left, gradients: gradients, hessians: hessians)
                    + gain(right, gradients: gradients, hessians: hessians)
                    - parentGain
                if improvement > (best?.improvement ?? 1e-9) {
                    best = (feature, threshold, improvement, left, right)
                }
            }
        }

        guard let best else { return .leaf(value: leafValue) }
        return .split(feature: best.feature,
                      threshold: best.threshold,
                      left: build(indices: best.left, features: features, gradients: gradients,
                                  hessians: hessians, featureSubset: featureSubset, depth: depth + 1),
                      right: build(indices: best.right, features: features, gradients: gradients,
                                   hessians: hessians, featureSubset: featureSubset, depth: depth + 1))
    }

    /// Passo di Newton regolarizzato.
    private func leafValue(_ indices: [Int], gradients: [Double], hessians: [Double]) -> Double {
        guard !indices.isEmpty else { return 0 }
        let gradientSum = indices.reduce(0.0) { $0 + gradients[$1] }
        let hessianSum = indices.reduce(0.0) { $0 + hessians[$1] }
        return gradientSum / (hessianSum + lambda)
    }

    /// Punteggio strutturale di un nodo: `G² / (H + λ)`.
    private func gain(_ indices: [Int], gradients: [Double], hessians: [Double]) -> Double {
        guard !indices.isEmpty else { return 0 }
        let gradientSum = indices.reduce(0.0) { $0 + gradients[$1] }
        let hessianSum = indices.reduce(0.0) { $0 + hessians[$1] }
        return gradientSum * gradientSum / (hessianSum + lambda)
    }
}

/// Gradient boosting per classificazione binaria con perdita logistica.
///
/// È la stessa famiglia di algoritmi di XGBoost e LightGBM — che non sono
/// disponibili come librerie su iOS — implementata con i soli framework di sistema:
/// alberi di regressione additivi, passo di Newton nelle foglie, learning rate,
/// campionamento di righe e colonne.
///
/// - Important: come per gli altri modelli, serve a **misurare** quanto le feature
///   storiche siano informative. Su un processo casuale il risultato atteso è
///   un'AUC indistinguibile da 0,500, ed è quello che l'app riporta.
final class GradientBoostingClassifier: @unchecked Sendable {

    private var trees: [RegressionTree] = []
    private var initialScore: Double = 0

    private let treeCount: Int
    private let maxDepth: Int
    private let learningRate: Double
    /// Frazione di righe estratta per ogni albero.
    private let subsample: Double
    /// Frazione di colonne considerata per ogni albero.
    private let colsample: Double

    init(treeCount: Int = 60,
         maxDepth: Int = 3,
         learningRate: Double = 0.1,
         subsample: Double = 0.8,
         colsample: Double = 0.8) {
        self.treeCount = treeCount
        self.maxDepth = maxDepth
        self.learningRate = learningRate
        self.subsample = subsample
        self.colsample = colsample
    }

    func train(features: [[Double]], labels: [Int], seed: UInt64 = 11) {
        guard !features.isEmpty, features.count == labels.count, let width = features.first?.count else { return }
        trees = []
        var generator = SeededRandom(seed: seed)

        // Punteggio iniziale: il log-odds della classe positiva.
        let positives = Double(labels.reduce(0, +))
        let rate = min(max(positives / Double(labels.count), 1e-6), 1 - 1e-6)
        initialScore = log(rate / (1 - rate))

        var scores = [Double](repeating: initialScore, count: features.count)
        let columnCount = max(1, Int((Double(width) * colsample).rounded()))

        for _ in 0..<treeCount {
            // Gradiente e hessiana della perdita logistica.
            var gradients = [Double](repeating: 0, count: features.count)
            var hessians = [Double](repeating: 0, count: features.count)
            for index in features.indices {
                let probability = Self.sigmoid(scores[index])
                gradients[index] = Double(labels[index]) - probability
                hessians[index] = max(probability * (1 - probability), 1e-6)
            }

            // Campionamento di righe e colonne.
            var rowFeatures: [[Double]] = []
            var rowGradients: [Double] = []
            var rowHessians: [Double] = []
            rowFeatures.reserveCapacity(features.count)
            for index in features.indices where generator.nextUnit() < subsample {
                rowFeatures.append(features[index])
                rowGradients.append(gradients[index])
                rowHessians.append(hessians[index])
            }
            guard rowFeatures.count > 40 else { continue }

            var available = Array(0..<width)
            var subset: [Int] = []
            for _ in 0..<columnCount where !available.isEmpty {
                subset.append(available.remove(at: Int(generator.next() % UInt64(available.count))))
            }

            let tree = RegressionTree(maxDepth: maxDepth, minSamples: max(20, rowFeatures.count / 100))
            tree.train(features: rowFeatures, gradients: rowGradients, hessians: rowHessians, featureSubset: subset)
            trees.append(tree)

            for index in features.indices {
                scores[index] += learningRate * tree.predict(features[index])
            }
        }
    }

    func predictProbability(_ feature: [Double]) -> Double {
        var score = initialScore
        for tree in trees { score += learningRate * tree.predict(feature) }
        return Self.sigmoid(score)
    }

    var trainedTreeCount: Int { trees.count }

    @inline(__always)
    static func sigmoid(_ value: Double) -> Double {
        1 / (1 + exp(-value))
    }
}
