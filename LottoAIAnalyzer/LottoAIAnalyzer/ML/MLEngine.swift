import Foundation

/// Modelli disponibili nel modulo sperimentale.
enum MLModelKind: String, CaseIterable, Identifiable, Sendable {
    case logisticRegression
    case randomForest
    case clustering
    case bayesian
    case anomalyDetection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .logisticRegression: return "Regressione logistica"
        case .randomForest: return "Random Forest"
        case .clustering: return "Clustering (k-means)"
        case .bayesian: return "Modello bayesiano"
        case .anomalyDetection: return "Rilevazione anomalie"
        }
    }

    var purpose: String {
        switch self {
        case .logisticRegression:
            return "Misura quanto le feature storiche siano informative rispetto all'esito di un'estrazione."
        case .randomForest:
            return "Insieme di alberi decisionali usato per il ranking statistico e il confronto con la baseline."
        case .clustering:
            return "Raggruppa i numeri per profilo statistico (frequenza, ritardo, trend, volatilità)."
        case .bayesian:
            return "Stima la probabilità a posteriori di ciascun numero e la confronta con quella teorica."
        case .anomalyDetection:
            return "Individua i numeri il cui profilo statistico si discosta di più dalla media."
        }
    }
}

/// Esito della valutazione di un modello supervisionato.
struct MLEvaluation: Sendable {
    var modelName: String
    var trainingSamples: Int
    var testSamples: Int
    /// Accuratezza del modello sul test set.
    var accuracy: Double
    /// Accuratezza della baseline che predice sempre la classe maggioritaria.
    var baselineAccuracy: Double
    /// Area sotto la curva ROC (0.5 = nessuna capacità discriminante).
    var auc: Double
    var logLoss: Double
    var baselineLogLoss: Double
    var significance: TestResult

    var improvement: Double { accuracy - baselineAccuracy }

    var verdict: String {
        // L'AUC è la metrica onesta su classi fortemente sbilanciate.
        if auc <= 0.53 && !significance.isSignificant {
            return "\(Disclaimer.noEdge) L'AUC è \(String(format: "%.3f", auc)), praticamente indistinguibile dal valore 0,500 di un classificatore casuale."
        }
        if significance.isSignificant {
            return "Il modello mostra una differenza statisticamente significativa rispetto alla baseline sul campione di test (AUC \(String(format: "%.3f", auc))). Su un processo casuale un risultato del genere è quasi sempre effetto della variabilità campionaria o di uno sbilanciamento delle classi: non va interpretato come capacità predittiva."
        }
        return "\(Disclaimer.noEdge) Le differenze rispetto alla baseline rientrano nella normale variabilità campionaria."
    }
}

/// Gruppo di numeri con profilo statistico simile.
struct NumberCluster: Identifiable, Sendable {
    let index: Int
    let numbers: [Int]
    let profile: String
    var id: Int { index }
    var title: String { "Gruppo \(index + 1)" }
}

/// Profilo anomalo di un numero.
struct AnomalyScore: Identifiable, Sendable {
    let number: Int
    /// Distanza di Mahalanobis semplificata dal profilo medio.
    let distance: Double
    let explanation: String

    var id: Int { number }
}

/// Coordina i modelli sperimentali di machine learning.
///
/// - Important: nessuno di questi modelli viene presentato come capace di
///   prevedere un'estrazione casuale. Servono a classificare pattern storici,
///   raggruppare numeri, misurare co-occorrenze, rilevare anomalie e — soprattutto —
///   a quantificare onestamente l'assenza di potere predittivo.
enum MLEngine {

    // MARK: - Valutazione supervisionata walk-forward

    /// Addestra un modello sui dati più vecchi e lo valuta su quelli più recenti.
    /// Lo split è temporale: nessun dato futuro entra nell'addestramento.
    static func evaluate(kind: MLModelKind,
                         draws: [DrawRecord],
                         game: GameType,
                         progress: (@Sendable (Double) -> Void)? = nil) -> MLEvaluation? {
        progress?(0.05)
        let dataset = MLFeatureBuilder.supervisedDataset(draws: draws, game: game)
        guard dataset.features.count > 500 else { return nil }
        progress?(0.35)

        // Split temporale 70/30: il dataset è già in ordine cronologico.
        let splitIndex = Int(Double(dataset.features.count) * 0.7)
        let trainFeatures = Array(dataset.features[0..<splitIndex])
        let trainLabels = Array(dataset.labels[0..<splitIndex])
        let testFeatures = Array(dataset.features[splitIndex...])
        let testLabels = Array(dataset.labels[splitIndex...])
        guard !testFeatures.isEmpty else { return nil }

        var probabilities: [Double] = []
        let name: String

        switch kind {
        case .randomForest:
            name = MLModelKind.randomForest.displayName
            let forest = RandomForest(treeCount: 20, maxDepth: 5)
            forest.train(features: trainFeatures, labels: trainLabels)
            progress?(0.8)
            probabilities = testFeatures.map { forest.predictProbability($0) }
        default:
            name = MLModelKind.logisticRegression.displayName
            var model = LogisticRegression(featureCount: trainFeatures[0].count)
            model.train(features: trainFeatures, labels: trainLabels)
            progress?(0.8)
            probabilities = testFeatures.map { model.predictProbability($0) }
        }

        let positiveRate = Double(trainLabels.reduce(0, +)) / Double(trainLabels.count)
        let predictions = probabilities.map { $0 >= 0.5 ? 1 : 0 }
        let correct = zip(predictions, testLabels).filter { $0 == $1 }.count
        let accuracy = Double(correct) / Double(testLabels.count)

        // Baseline: predice sempre la classe maggioritaria (quasi sempre "non esce").
        let majority = positiveRate >= 0.5 ? 1 : 0
        let baselineCorrect = testLabels.filter { $0 == majority }.count
        let baselineAccuracy = Double(baselineCorrect) / Double(testLabels.count)

        let significance = StatisticalTests.twoProportionZTest(
            successesA: correct, trialsA: testLabels.count,
            successesB: baselineCorrect, trialsB: testLabels.count,
            name: "\(name) contro baseline")

        progress?(1)
        return MLEvaluation(modelName: name,
                            trainingSamples: trainFeatures.count,
                            testSamples: testFeatures.count,
                            accuracy: accuracy,
                            baselineAccuracy: baselineAccuracy,
                            auc: areaUnderROC(probabilities: probabilities, labels: testLabels),
                            logLoss: logLoss(probabilities: probabilities, labels: testLabels),
                            baselineLogLoss: logLoss(probabilities: Array(repeating: positiveRate, count: testLabels.count),
                                                     labels: testLabels),
                            significance: significance)
    }

    // MARK: - Clustering

    static func clusterNumbers(context: AnalysisContext, clusters: Int = 4) -> [NumberCluster] {
        let features = MLFeatureBuilder.numberFeatures(context: context)
        guard features.count >= clusters else { return [] }
        let result = KMeans.fit(points: features.map(\.vector), clusters: clusters, seed: 17)

        var grouped: [Int: [Int]] = [:]
        for (index, cluster) in result.assignments.enumerated() {
            grouped[cluster, default: []].append(features[index].number)
        }

        return grouped.sorted { $0.key < $1.key }.map { cluster, numbers in
            NumberCluster(index: cluster,
                          numbers: numbers.sorted(),
                          profile: describeCentroid(result.centroids[cluster]))
        }
    }

    private static func describeCentroid(_ centroid: [Double]) -> String {
        guard centroid.count >= 6 else { return "Profilo non disponibile." }
        func level(_ value: Double) -> String {
            switch value {
            case ..<0.34: return "bassa"
            case ..<0.67: return "media"
            default: return "alta"
            }
        }
        return "Frequenza \(level(centroid[0])), ritardo \(level(centroid[1])), trend \(level(centroid[2])), volatilità \(level(centroid[3]))."
    }

    // MARK: - Anomalie

    static func anomalies(context: AnalysisContext, limit: Int = 10) -> [AnomalyScore] {
        let features = MLFeatureBuilder.numberFeatures(context: context)
        guard !features.isEmpty else { return [] }
        let dimensions = features[0].vector.count
        var means = [Double](repeating: 0, count: dimensions)
        for feature in features {
            for dimension in 0..<dimensions { means[dimension] += feature.vector[dimension] }
        }
        means = means.map { $0 / Double(features.count) }

        var deviations = [Double](repeating: 0, count: dimensions)
        for feature in features {
            for dimension in 0..<dimensions {
                deviations[dimension] += pow(feature.vector[dimension] - means[dimension], 2)
            }
        }
        deviations = deviations.map { max(($0 / Double(features.count)).squareRoot(), 1e-6) }

        let scored = features.map { feature -> AnomalyScore in
            var distance = 0.0
            var strongest = (name: "", value: 0.0)
            for dimension in 0..<dimensions {
                let z = (feature.vector[dimension] - means[dimension]) / deviations[dimension]
                distance += z * z
                if abs(z) > abs(strongest.value) {
                    strongest = (NumberFeatureVector.featureNames[dimension], z)
                }
            }
            let direction = strongest.value > 0 ? "sopra" : "sotto"
            return AnomalyScore(number: feature.number,
                                distance: distance.squareRoot(),
                                explanation: String(format: "Scostamento maggiore su «%@»: %.1f deviazioni standard %@ la media.",
                                                    strongest.name, abs(strongest.value), direction))
        }
        return Array(scored.sorted { $0.distance > $1.distance }.prefix(limit))
    }

    // MARK: - Metriche

    /// Area sotto la curva ROC calcolata con la statistica di Mann–Whitney.
    static func areaUnderROC(probabilities: [Double], labels: [Int]) -> Double {
        let positives = zip(probabilities, labels).filter { $0.1 == 1 }.map(\.0)
        let negatives = zip(probabilities, labels).filter { $0.1 == 0 }.map(\.0)
        guard !positives.isEmpty, !negatives.isEmpty else { return 0.5 }

        let combined = (positives.map { ($0, 1) } + negatives.map { ($0, 0) })
            .sorted { $0.0 < $1.0 }
        var ranks = [Double](repeating: 0, count: combined.count)
        var index = 0
        while index < combined.count {
            var end = index
            while end + 1 < combined.count && combined[end + 1].0 == combined[index].0 { end += 1 }
            let averageRank = Double(index + end) / 2 + 1
            for position in index...end { ranks[position] = averageRank }
            index = end + 1
        }
        var positiveRankSum = 0.0
        for (position, item) in combined.enumerated() where item.1 == 1 {
            positiveRankSum += ranks[position]
        }
        let positiveCount = Double(positives.count)
        let negativeCount = Double(negatives.count)
        return (positiveRankSum - positiveCount * (positiveCount + 1) / 2) / (positiveCount * negativeCount)
    }

    static func logLoss(probabilities: [Double], labels: [Int]) -> Double {
        guard !probabilities.isEmpty else { return 0 }
        var total = 0.0
        for (probability, label) in zip(probabilities, labels) {
            let clamped = Swift.min(Swift.max(probability, 1e-9), 1 - 1e-9)
            total += label == 1 ? -log(clamped) : -log(1 - clamped)
        }
        return total / Double(probabilities.count)
    }
}
