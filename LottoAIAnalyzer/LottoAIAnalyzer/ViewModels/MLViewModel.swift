import Foundation
import Observation

@MainActor
@Observable
final class MLViewModel {

    var filter: AnalysisFilter
    var selectedModel: MLModelKind = .logisticRegression
    var evaluation: MLEvaluation?
    var clusters: [NumberCluster] = []
    var anomalies: [AnomalyScore] = []
    var posteriors: [BayesianModel.Posterior] = []
    var bayesianSummary: String?
    var isRunning = false
    var message: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        self.filter = app.settings.defaultFilter()
    }

    func run() async {
        isRunning = true
        message = nil
        defer { isRunning = false }

        let currentFilter = filter
        let weights = app.settings.weights
        let draws = app.draws(for: currentFilter.game)
        let model = selectedModel

        let context = await app.compute {
            AnalysisContext(filter: currentFilter, allDraws: draws, weights: weights)
        }
        guard !context.isEmpty else {
            message = "Nessuna estrazione disponibile per il filtro selezionato."
            return
        }

        switch model {
        case .clustering:
            clusters = await app.compute { MLEngine.clusterNumbers(context: context, clusters: 4) }
        case .anomalyDetection:
            anomalies = await app.compute { MLEngine.anomalies(context: context, limit: 12) }
        case .bayesian:
            let bayes = BayesianModel()
            let computed = await app.compute { bayes.posteriors(context: context) }
            posteriors = computed
            bayesianSummary = bayes.summary(for: computed)
        case .logisticRegression, .randomForest, .gradientBoosting:
            let game = currentFilter.game
            let contextDraws = context.draws
            let outcome = await app.compute {
                MLEngine.evaluate(kind: model, draws: contextDraws, game: game)
            }
            evaluation = outcome
            if outcome == nil {
                message = "Storico insufficiente per addestrare il modello: servono almeno alcune centinaia di estrazioni."
            }
        }
    }
}
