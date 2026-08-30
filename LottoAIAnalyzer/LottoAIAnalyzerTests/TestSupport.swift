import Foundation
@testable import LottoAIAnalyzer

/// Utilità condivise dai test.
enum TestSupport {

    static func date(_ string: String) -> Date {
        DrawParser.parseDate(string) ?? Date()
    }

    /// Estrazioni deterministiche per il gioco indicato.
    static func draws(count: Int,
                      game: GameType = .lotto,
                      wheel: Wheel? = .bari,
                      seed: UInt64 = 99,
                      startingAt start: String = "2020-01-07") -> [DrawRecord] {
        var generator = SeededRandom(seed: seed)
        var records: [DrawRecord] = []
        var current = date(start)
        for _ in 0..<count {
            var pool = Array(1...90)
            for position in 0..<game.drawnCount {
                let swapIndex = position + Int(generator.next() % UInt64(90 - position))
                pool.swapAt(position, swapIndex)
            }
            records.append(DrawRecord(date: current,
                                      game: game,
                                      wheel: game.usesWheels ? wheel : nil,
                                      numbers: Array(pool.prefix(game.drawnCount))))
            current = Calendar.italian.date(byAdding: .day, value: 3, to: current) ?? current
        }
        return records
    }

    /// Estrazioni costruite a mano, una per riga di numeri.
    static func draws(_ combinations: [[Int]],
                      game: GameType = .lotto,
                      wheel: Wheel? = .bari,
                      startingAt start: String = "2024-01-02") -> [DrawRecord] {
        var current = date(start)
        return combinations.map { numbers in
            let record = DrawRecord(date: current,
                                    game: game,
                                    wheel: game.usesWheels ? wheel : nil,
                                    numbers: numbers)
            current = Calendar.italian.date(byAdding: .day, value: 3, to: current) ?? current
            return record
        }
    }

    static func context(_ records: [DrawRecord],
                        game: GameType = .lotto,
                        wheel: Wheel? = .bari,
                        period: AnalysisPeriod = .all,
                        weights: ScoringWeights = .balanced) -> AnalysisContext {
        let filter = AnalysisFilter(game: game,
                                    wheelScope: wheel.map { WheelScope.single($0) } ?? .all,
                                    period: period)
        return AnalysisContext(filter: filter, allDraws: records, weights: weights)
    }
}
