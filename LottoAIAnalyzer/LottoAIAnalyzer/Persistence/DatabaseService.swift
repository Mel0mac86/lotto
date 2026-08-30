import Foundation
import SwiftData

/// Errori generati dal livello di persistenza.
enum DatabaseError: LocalizedError {
    case invalidNumbers(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidNumbers(let detail): return "Numeri non validi: \(detail)"
        case .saveFailed(let detail): return "Salvataggio non riuscito: \(detail)"
        }
    }
}

/// Esito di un'operazione di importazione.
struct ImportResult: Sendable {
    var inserted: Int = 0
    var duplicates: Int = 0
    var rejected: Int = 0
    var errors: [String] = []

    var total: Int { inserted + duplicates + rejected }

    var summary: String {
        var lines = ["\(inserted) estrazioni importate", "\(duplicates) duplicati ignorati"]
        if rejected > 0 { lines.append("\(rejected) righe scartate") }
        return lines.joined(separator: " · ")
    }

    static func + (lhs: ImportResult, rhs: ImportResult) -> ImportResult {
        ImportResult(inserted: lhs.inserted + rhs.inserted,
                     duplicates: lhs.duplicates + rhs.duplicates,
                     rejected: lhs.rejected + rhs.rejected,
                     errors: lhs.errors + rhs.errors)
    }
}

/// Unico punto di accesso al database. Gli engine di analisi non conoscono SwiftData:
/// ricevono sempre array di `DrawRecord`.
@MainActor
final class DatabaseService {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Lettura

    func allDraws(game: GameType) throws -> [DrawRecord] {
        let raw = game.rawValue
        var descriptor = FetchDescriptor<Draw>(
            predicate: #Predicate { $0.gameRaw == raw },
            sortBy: [SortDescriptor(\.date, order: .forward)])
        descriptor.fetchLimit = nil
        return try context.fetch(descriptor).map(\.record)
    }

    func drawCount(game: GameType) throws -> Int {
        let raw = game.rawValue
        let descriptor = FetchDescriptor<Draw>(predicate: #Predicate { $0.gameRaw == raw })
        return try context.fetchCount(descriptor)
    }

    func latestDrawDate(game: GameType) throws -> Date? {
        let raw = game.rawValue
        var descriptor = FetchDescriptor<Draw>(
            predicate: #Predicate { $0.gameRaw == raw },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.date
    }

    func availableYears(game: GameType) throws -> [Int] {
        let records = try allDraws(game: game)
        return Array(Set(records.map(\.year))).sorted(by: >)
    }

    // MARK: - Scrittura

    /// Inserisce le estrazioni scartando i duplicati (chiave `dedupeKey`).
    @discardableResult
    func insert(_ records: [DrawRecord], source: String) throws -> ImportResult {
        var result = ImportResult()
        let existing = try existingKeys()
        var seenInBatch = Set<String>()

        for record in records {
            guard validate(record) else {
                result.rejected += 1
                continue
            }
            let key = Draw.makeDedupeKey(date: record.date,
                                         game: record.game,
                                         wheel: record.wheel,
                                         numbers: record.numbers)
            if existing.contains(key) || seenInBatch.contains(key) {
                result.duplicates += 1
                continue
            }
            seenInBatch.insert(key)
            let draw = Draw(date: record.date,
                            game: record.game,
                            wheel: record.wheel,
                            numbers: record.numbers,
                            jolly: record.jolly,
                            superstar: record.superstar,
                            source: source)
            context.insert(draw)
            result.inserted += 1
        }

        if result.inserted > 0 {
            do { try context.save() }
            catch { throw DatabaseError.saveFailed(error.localizedDescription) }
        }
        return result
    }

    func deleteAll(game: GameType) throws {
        let raw = game.rawValue
        try context.delete(model: Draw.self, where: #Predicate { $0.gameRaw == raw })
        try context.save()
    }

    func save(_ combination: ScoredCombination,
              game: GameType,
              wheel: Wheel?,
              strategy: GenerationStrategy,
              period: AnalysisPeriod) throws {
        let saved = SavedCombination(combination: combination,
                                     game: game,
                                     wheel: wheel,
                                     strategy: strategy,
                                     period: period)
        context.insert(saved)
        try context.save()
    }

    func savedCombinations() throws -> [SavedCombination] {
        let descriptor = FetchDescriptor<SavedCombination>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    func delete(_ combination: SavedCombination) throws {
        context.delete(combination)
        try context.save()
    }

    // MARK: - Helper

    private func existingKeys() throws -> Set<String> {
        var descriptor = FetchDescriptor<Draw>()
        // Serve solo la chiave di deduplica: evita di materializzare l'intero archivio.
        descriptor.propertiesToFetch = [\.dedupeKey]
        return Set(try context.fetch(descriptor).map(\.dedupeKey))
    }

    private func validate(_ record: DrawRecord) -> Bool {
        guard record.numbers.count == record.game.drawnCount else { return false }
        guard Set(record.numbers).count == record.numbers.count else { return false }
        guard record.numbers.allSatisfy({ record.game.numberRange.contains($0) }) else { return false }
        if record.game.usesWheels && record.wheel == nil { return false }
        if let jolly = record.jolly, !(1...90).contains(jolly) { return false }
        if let superstar = record.superstar, !(1...90).contains(superstar) { return false }
        return true
    }
}
