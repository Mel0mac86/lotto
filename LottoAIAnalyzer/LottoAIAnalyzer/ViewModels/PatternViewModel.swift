import Foundation
import Observation

@MainActor
@Observable
final class PatternViewModel {

    var filter: AnalysisFilter
    var patterns: [DetectedPattern] = []
    var isRunning = false

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        self.filter = app.settings.defaultFilter()
    }

    func run() async {
        isRunning = true
        defer { isRunning = false }
        let currentFilter = filter
        let weights = app.settings.weights
        let draws = app.draws(for: currentFilter.game)

        patterns = await app.compute {
            let context = AnalysisContext(filter: currentFilter, allDraws: draws, weights: weights)
            return PatternFinder.analyze(context: context)
        }
    }

    var grouped: [PatternGroup] {
        DetectedPattern.Category.allCases.compactMap { category in
            let items = patterns.filter { $0.category == category }
            return items.isEmpty ? nil : PatternGroup(category: category, items: items)
        }
    }

    var noteworthyCount: Int { patterns.filter(\.isNoteworthy).count }
}

/// Gruppo di pattern appartenenti alla stessa categoria.
struct PatternGroup: Identifiable, Sendable {
    let category: DetectedPattern.Category
    let items: [DetectedPattern]
    var id: String { category.rawValue }
}
