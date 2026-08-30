import Foundation

/// Albero decisionale CART per classificazione binaria, con criterio di Gini.
final class DecisionTree: @unchecked Sendable {

    private indirect enum Node {
        case leaf(probability: Double)
        case split(feature: Int, threshold: Double, left: Node, right: Node)
    }

    private var root: Node = .leaf(probability: 0.5)
    private let maxDepth: Int
    private let minSamples: Int

    init(maxDepth: Int = 6, minSamples: Int = 25) {
        self.maxDepth = maxDepth
        self.minSamples = minSamples
    }

    func train(features: [[Double]], labels: [Int], featureSubset: [Int]? = nil, seed: UInt64 = 1) {
        guard !features.isEmpty else { return }
        var generator = SeededRandom(seed: seed)
        let indices = Array(features.indices)
        root = build(indices: indices,
                     features: features,
                     labels: labels,
                     depth: 0,
                     featureSubset: featureSubset,
                     generator: &generator)
    }

    func predictProbability(_ feature: [Double]) -> Double {
        var node = root
        while true {
            switch node {
            case .leaf(let probability):
                return probability
            case .split(let index, let threshold, let left, let right):
                node = (index < feature.count && feature[index] <= threshold) ? left : right
            }
        }
    }

    private func build(indices: [Int],
                       features: [[Double]],
                       labels: [Int],
                       depth: Int,
                       featureSubset: [Int]?,
                       generator: inout SeededRandom) -> Node {
        let positives = indices.reduce(0) { $0 + labels[$1] }
        let probability = indices.isEmpty ? 0.5 : Double(positives) / Double(indices.count)

        guard depth < maxDepth, indices.count >= minSamples, positives > 0, positives < indices.count else {
            return .leaf(probability: probability)
        }

        let candidateFeatures = featureSubset ?? Array(0..<(features.first?.count ?? 0))
        var best: (feature: Int, threshold: Double, gain: Double, left: [Int], right: [Int])?
        let parentImpurity = gini(probability)

        for feature in candidateFeatures {
            // Quartili stimati su un campione dei valori: ordinarli tutti a ogni nodo
            // è la parte più costosa dell'addestramento.
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
            let thresholds = [0.25, 0.5, 0.75].map { values[Int(Double(values.count - 1) * $0)] }
            for threshold in Set(thresholds) {
                var left: [Int] = [], right: [Int] = []
                for index in indices {
                    if features[index][feature] <= threshold { left.append(index) } else { right.append(index) }
                }
                guard left.count >= minSamples / 2, right.count >= minSamples / 2 else { continue }
                let leftProbability = Double(left.reduce(0) { $0 + labels[$1] }) / Double(left.count)
                let rightProbability = Double(right.reduce(0) { $0 + labels[$1] }) / Double(right.count)
                let weighted = (Double(left.count) * gini(leftProbability) + Double(right.count) * gini(rightProbability))
                    / Double(indices.count)
                let gain = parentImpurity - weighted
                if gain > (best?.gain ?? 1e-9) {
                    best = (feature, threshold, gain, left, right)
                }
            }
        }

        guard let best else { return .leaf(probability: probability) }
        let left = build(indices: best.left, features: features, labels: labels, depth: depth + 1,
                         featureSubset: featureSubset, generator: &generator)
        let right = build(indices: best.right, features: features, labels: labels, depth: depth + 1,
                          featureSubset: featureSubset, generator: &generator)
        return .split(feature: best.feature, threshold: best.threshold, left: left, right: right)
    }

    private func gini(_ probability: Double) -> Double {
        2 * probability * (1 - probability)
    }
}

/// Random Forest: insieme di alberi addestrati su campioni bootstrap
/// e su sottoinsiemi casuali di feature.
final class RandomForest: @unchecked Sendable {
    private var trees: [DecisionTree] = []
    private let treeCount: Int
    private let maxDepth: Int

    init(treeCount: Int = 25, maxDepth: Int = 6) {
        self.treeCount = treeCount
        self.maxDepth = maxDepth
    }

    func train(features: [[Double]], labels: [Int], seed: UInt64 = 3) {
        guard !features.isEmpty else { return }
        var generator = SeededRandom(seed: seed)
        let featureCount = features[0].count
        let subsetSize = max(2, Int(Double(featureCount).squareRoot().rounded()))
        trees = []

        for treeIndex in 0..<treeCount {
            // Bootstrap.
            var bootstrapFeatures: [[Double]] = []
            var bootstrapLabels: [Int] = []
            bootstrapFeatures.reserveCapacity(features.count)
            for _ in 0..<features.count {
                let index = Int(generator.next() % UInt64(features.count))
                bootstrapFeatures.append(features[index])
                bootstrapLabels.append(labels[index])
            }
            // Sottoinsieme casuale di feature.
            var available = Array(0..<featureCount)
            var subset: [Int] = []
            for _ in 0..<subsetSize where !available.isEmpty {
                let index = Int(generator.next() % UInt64(available.count))
                subset.append(available.remove(at: index))
            }
            let tree = DecisionTree(maxDepth: maxDepth)
            tree.train(features: bootstrapFeatures, labels: bootstrapLabels,
                       featureSubset: subset, seed: generator.next())
            trees.append(tree)
            _ = treeIndex
        }
    }

    func predictProbability(_ feature: [Double]) -> Double {
        guard !trees.isEmpty else { return 0.5 }
        return trees.reduce(0.0) { $0 + $1.predictProbability(feature) } / Double(trees.count)
    }
}
