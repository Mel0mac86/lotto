import Foundation
import SwiftData
import Observation

/// Stato condiviso dell'applicazione: accesso al database, impostazioni,
/// costruzione dei contesti di analisi e stato dell'aggiornamento automatico.
@MainActor
@Observable
final class AppModel {

    let settings: AppSettings
    let database: DatabaseService
    let updater: AutoUpdateService

    /// Estrazioni caricate in memoria, per gioco.
    private var cachedDraws: [GameType: [DrawRecord]] = [:]

    var isBusy = false
    var statusMessage: String?
    var lastError: String?
    var lastUpdateOutcome: UpdateOutcome?

    init(container: ModelContainer, settings: AppSettings = AppSettings()) {
        let database = DatabaseService(container: container)
        self.settings = settings
        self.database = database
        self.updater = AutoUpdateService(database: database, settings: settings)
    }

    // MARK: - Dati

    func draws(for game: GameType) -> [DrawRecord] {
        if let cached = cachedDraws[game] { return cached }
        do {
            let records = try database.allDraws(game: game)
            cachedDraws[game] = records
            return records
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func reloadDraws() {
        cachedDraws.removeAll()
        AnalysisCache.shared.invalidateAll()
    }

    func drawCount(for game: GameType) -> Int { draws(for: game).count }

    func latestDate(for game: GameType) -> Date? { draws(for: game).last?.date }

    func availableYears(for game: GameType) -> [Int] {
        Array(Set(draws(for: game).map(\.year))).sorted(by: >)
    }

    var hasAnyData: Bool { !draws(for: .lotto).isEmpty || !draws(for: .superenalotto).isEmpty }

    // MARK: - Contesti di analisi

    /// Costruisce (o riusa) il contesto di analisi per il filtro indicato.
    func context(for filter: AnalysisFilter, weights: ScoringWeights? = nil) -> AnalysisContext {
        let effectiveWeights = weights ?? settings.weights
        return AnalysisCache.shared.context(for: filter,
                                            weights: effectiveWeights,
                                            draws: self.draws(for: filter.game))
    }

    /// Esegue un calcolo pesante fuori dal main actor.
    func compute<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    // MARK: - Import

    @discardableResult
    func importFile(at url: URL, defaultGame: GameType) async -> ImportResult {
        isBusy = true
        defer { isBusy = false }
        do {
            let records = try ImportCoordinator.parse(fileURL: url, defaultGame: defaultGame)
            let result = try database.insert(records, source: url.lastPathComponent)
            reloadDraws()
            statusMessage = result.summary
            return result
        } catch {
            lastError = error.localizedDescription
            return ImportResult(inserted: 0, duplicates: 0, rejected: 0, errors: [error.localizedDescription])
        }
    }

    @discardableResult
    func importSeedData() async -> ImportResult {
        isBusy = true
        defer { isBusy = false }
        do {
            let records = try SeedDataProvider.loadBundledSamples()
            let result = try database.insert(records, source: "dati di esempio")
            reloadDraws()
            statusMessage = result.summary
            return result
        } catch {
            lastError = error.localizedDescription
            return ImportResult()
        }
    }

    func deleteAll(game: GameType) {
        do {
            try database.deleteAll(game: game)
            reloadDraws()
            statusMessage = "Archivio \(game.displayName) svuotato."
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Aggiornamento

    func runUpdate() async {
        isBusy = true
        defer { isBusy = false }
        let outcome = await updater.runUpdateCycle()
        lastUpdateOutcome = outcome
        if outcome.hasNewData { reloadDraws() }
        statusMessage = outcome.message
    }

    // MARK: - Combinazioni salvate

    func save(_ combination: ScoredCombination, filter: AnalysisFilter, strategy: GenerationStrategy) {
        do {
            let wheel: Wheel?
            if case .single(let value) = filter.wheelScope { wheel = value } else { wheel = nil }
            try database.save(combination, game: filter.game, wheel: wheel,
                              strategy: strategy, period: filter.period)
            statusMessage = "Combinazione salvata."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func savedCombinations() -> [SavedCombination] {
        (try? database.savedCombinations()) ?? []
    }

    func delete(_ combination: SavedCombination) {
        do { try database.delete(combination) } catch { lastError = error.localizedDescription }
    }
}
