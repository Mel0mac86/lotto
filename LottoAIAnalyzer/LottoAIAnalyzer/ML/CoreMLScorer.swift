import Foundation
import CoreML

/// Punto di innesto per un modello Core ML esterno.
///
/// L'app funziona interamente con i modelli scritti in Swift (`LogisticRegression`,
/// `RandomForest`, `GradientBoostingClassifier`, `KMeans`, `BayesianModel`). Questo
/// adattatore permette, in più, di far cadere nel bundle un modello addestrato altrove
/// — per esempio in Python con scikit-learn o XGBoost e convertito con `coremltools` —
/// senza toccare il resto del codice: se il file c'è viene usato, altrimenti si resta
/// sui modelli interni.
///
/// Il modello deve accettare le feature di `MLFeatureBuilder` come input `Double`
/// con i nomi indicati in `featureNames` ed esporre una probabilità.
///
/// - Important: un modello Core ML non cambia la natura del problema. Le estrazioni
///   restano casuali: qualunque modello, interno o importato, viene comunque valutato
///   dall'app con split temporale e AUC, e il risultato viene riportato per quello che è.
struct CoreMLScorer {

    let model: MLModel
    let featureNames: [String]
    let outputName: String

    /// Nomi usati per default: corrispondono all'ordine di `MLFeatureBuilder`.
    static let defaultFeatureNames = ["frequenza", "ritardo", "trend", "volatilita", "cooccorrenza", "recenza"]

    /// Carica un modello compilato (`.mlmodelc`) dal bundle dell'app.
    /// Restituisce `nil` se il file non c'è: è il caso normale.
    static func load(named name: String,
                     featureNames: [String] = defaultFeatureNames,
                     outputName: String = "probability") -> CoreMLScorer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url) else { return nil }
        return CoreMLScorer(model: model, featureNames: featureNames, outputName: outputName)
    }

    /// Probabilità della classe positiva, oppure `nil` se il modello non risponde
    /// nel formato atteso.
    func probability(for features: [Double]) -> Double? {
        var inputs: [String: Any] = [:]
        for (index, name) in featureNames.enumerated() where index < features.count {
            inputs[name] = features[index]
        }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: inputs),
              let output = try? model.prediction(from: provider),
              let value = output.featureValue(for: outputName) else { return nil }

        switch value.type {
        case .double, .int64:
            return value.doubleValue
        case .dictionary:
            // I classificatori Core ML espongono la probabilità come dizionario classe → valore.
            let dictionary = value.dictionaryValue
            if let positive = dictionary[1 as NSNumber] ?? dictionary["1"] {
                return positive.doubleValue
            }
            return nil
        default:
            return nil
        }
    }

    /// Descrizione leggibile del modello caricato, mostrata nella schermata AI Analyst.
    var summary: String {
        let description = model.modelDescription
        let inputs = description.inputDescriptionsByName.keys.sorted().joined(separator: ", ")
        let outputs = description.outputDescriptionsByName.keys.sorted().joined(separator: ", ")
        return "Modello Core ML esterno · input: \(inputs) · output: \(outputs)"
    }
}
