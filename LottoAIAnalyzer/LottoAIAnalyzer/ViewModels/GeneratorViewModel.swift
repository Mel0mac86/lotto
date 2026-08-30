import Foundation
import Observation

/// Combinazione generata con il contesto che l'ha prodotta.
struct GeneratedResult: Identifiable, Sendable {
    let id = UUID()
    var combination: ScoredCombination
    var strategy: GenerationStrategy
    var filter: AnalysisFilter
    var explanation: [ExplanationSection]
    var isSelected: Bool = false
}

@MainActor
@Observable
final class GeneratorViewModel {

    // Parametri del generatore intelligente.
    var game: GameType
    var wheel: Wheel
    var useAllWheels = false
    var strategy: GenerationStrategy = .balanced
    var period: AnalysisPeriod = .fiveYears
    var quintupleMode: QuintupleMode = .balanced
    var combinationCount = 5

    // Risultati.
    var pairs: [PairResult] = []
    var triples: [TripleResult] = []
    var quintuples: [GeneratedResult] = []
    var multiWheelNumbers: [MultiWheelNumber] = []
    var multiWheelPairs: [MultiWheelSet] = []
    var multiWheelTriples: [MultiWheelSet] = []
    var multiWheelCombination: GeneratedResult?
    var multiWheelSignals: [Wheel] = []

    var isWorking = false
    var progressLabel: String?
    var errorMessage: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        self.game = app.settings.defaultGame
        self.wheel = app.settings.defaultWheel
        self.period = app.settings.defaultPeriod
    }

    var filter: AnalysisFilter {
        AnalysisFilter(game: game,
                       wheelScope: game.usesWheels ? (useAllWheels ? .all : .single(wheel)) : .all,
                       period: period)
    }

    private func makeContext() async -> AnalysisContext {
        let currentFilter = filter
        let weights = strategy.weights
        let draws = app.draws(for: game)
        return await app.compute {
            AnalysisContext(filter: currentFilter, allDraws: draws, weights: weights)
        }
    }

    // MARK: - Ambi

    func generatePairs(limit: Int = 10) async {
        await withWork("Analisi delle 4.005 coppie possibili…") {
            let context = await self.makeContext()
            guard !context.isEmpty else { self.pairs = []; return }
            self.pairs = await self.app.compute { PairGenerator.topPairs(context: context, limit: limit) }
        }
    }

    // MARK: - Terni

    func generateTriples(limit: Int = 10, poolSize: Int = 45) async {
        await withWork("Analisi delle combinazioni di tre numeri…") {
            let context = await self.makeContext()
            guard !context.isEmpty else { self.triples = []; return }
            self.triples = await self.app.compute {
                TripleGenerator.topTriples(context: context, limit: limit, poolSize: poolSize)
            }
        }
    }

    // MARK: - Cinquine

    func generateQuintuples() async {
        await withWork("Generazione delle combinazioni…") {
            let context = await self.makeContext()
            guard !context.isEmpty else { self.quintuples = []; return }
            let mode = self.quintupleMode
            let count = self.combinationCount
            let previous = self.quintuples.map(\.combination.numbers)
            let currentStrategy = self.strategy

            let combinations = await self.app.compute {
                QuintupleGenerator.generate(QuintupleGenerator.Request(
                    context: context,
                    mode: mode,
                    strategy: currentStrategy,
                    size: nil,
                    count: count,
                    seed: 0,
                    avoid: mode == .diversified ? previous : [],
                    candidateSamples: 4000))
            }

            let currentFilter = self.filter
            self.quintuples = combinations.map { combination in
                GeneratedResult(combination: combination,
                                strategy: currentStrategy,
                                filter: currentFilter,
                                explanation: AIExplainer.explain(combination: combination,
                                                                 context: context,
                                                                 strategy: currentStrategy))
            }
        }
    }

    // MARK: - Multi-ruota

    func loadMultiWheel() async {
        guard game.usesWheels else { return }
        await withWork("Analisi simultanea di tutte le ruote…") {
            let baseFilter = self.filter
            let weights = self.strategy.weights
            let draws = self.app.draws(for: .lotto)

            let contexts = await self.app.compute {
                MultiWheelEngine.buildContexts(filter: baseFilter, allDraws: draws, weights: weights)
            }
            guard !contexts.isEmpty else {
                self.multiWheelNumbers = []
                return
            }

            self.multiWheelNumbers = await self.app.compute { MultiWheelEngine.numbers(from: contexts) }
            self.multiWheelPairs = await self.app.compute { MultiWheelEngine.pairs(from: contexts) }
            self.multiWheelTriples = await self.app.compute { MultiWheelEngine.triples(from: contexts) }

            if let result = await self.app.compute({ MultiWheelEngine.multiWheelCombination(from: contexts) }) {
                let reference = contexts.contexts.values.max { $0.drawCount < $1.drawCount }
                self.multiWheelSignals = result.wheels
                self.multiWheelCombination = GeneratedResult(
                    combination: result.combination,
                    strategy: .multiWheel,
                    filter: baseFilter,
                    explanation: reference.map {
                        AIExplainer.explain(combination: result.combination, context: $0, strategy: .multiWheel)
                    } ?? [])
            }
        }
    }

    // MARK: - Selezione per il confronto

    func toggleSelection(_ result: GeneratedResult) {
        guard let index = quintuples.firstIndex(where: { $0.id == result.id }) else { return }
        if !quintuples[index].isSelected && selectedResults.count >= 10 { return }
        quintuples[index].isSelected.toggle()
    }

    var selectedResults: [GeneratedResult] { quintuples.filter(\.isSelected) }

    func save(_ result: GeneratedResult) {
        app.save(result.combination, filter: result.filter, strategy: result.strategy)
    }

    // MARK: - Helper

    private func withWork(_ label: String, _ operation: () async -> Void) async {
        isWorking = true
        progressLabel = label
        errorMessage = nil
        await operation()
        isWorking = false
        progressLabel = nil
    }
}
