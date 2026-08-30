import Foundation
import SwiftData

/// Entità persistente che rappresenta una singola estrazione.
///
/// Per il Lotto un record corrisponde a **una ruota** di una data estrazione
/// (5 numeri). Per il SuperEnalotto corrisponde all'estrazione completa
/// (6 numeri + jolly + superstar) e `wheelRaw` è `nil`.
@Model
final class Draw {
    /// Chiave di deduplica: `gioco|ruota|data|numeri`.
    @Attribute(.unique) var dedupeKey: String

    var date: Date
    var gameRaw: String
    var wheelRaw: String?

    var numero1: Int
    var numero2: Int
    var numero3: Int
    var numero4: Int
    var numero5: Int
    /// Vale 0 quando il gioco estrae solo 5 numeri (Lotto).
    var numero6: Int
    var jolly: Int?
    var superstar: Int?

    /// Origine del dato (import CSV, API, inserimento manuale…).
    var source: String
    var importedAt: Date

    init(date: Date,
         game: GameType,
         wheel: Wheel?,
         numbers: [Int],
         jolly: Int? = nil,
         superstar: Int? = nil,
         source: String = "manuale") {
        let padded = Draw.padded(numbers)
        self.date = date
        self.gameRaw = game.rawValue
        self.wheelRaw = wheel?.rawValue
        self.numero1 = padded[0]
        self.numero2 = padded[1]
        self.numero3 = padded[2]
        self.numero4 = padded[3]
        self.numero5 = padded[4]
        self.numero6 = padded[5]
        self.jolly = jolly
        self.superstar = superstar
        self.source = source
        self.importedAt = Date()
        self.dedupeKey = Draw.makeDedupeKey(date: date, game: game, wheel: wheel, numbers: numbers)
    }

    // MARK: - Derivati

    var game: GameType { GameType(rawValue: gameRaw) ?? .lotto }
    var wheel: Wheel? { wheelRaw.flatMap { Wheel(rawValue: $0) } }

    /// I numeri estratti, senza il riempimento a zero.
    var numbers: [Int] {
        [numero1, numero2, numero3, numero4, numero5, numero6].filter { $0 > 0 }
    }

    var record: DrawRecord {
        DrawRecord(date: date,
                   game: game,
                   wheel: wheel,
                   numbers: numbers,
                   jolly: jolly,
                   superstar: superstar)
    }

    // MARK: - Helper

    private static func padded(_ numbers: [Int]) -> [Int] {
        var result = numbers
        while result.count < 6 { result.append(0) }
        return Array(result.prefix(6))
    }

    static func makeDedupeKey(date: Date, game: GameType, wheel: Wheel?, numbers: [Int]) -> String {
        let day = DateFormatter.dedupeKeyFormatter.string(from: date)
        let sorted = numbers.sorted().map(String.init).joined(separator: "-")
        return "\(game.rawValue)|\(wheel?.rawValue ?? "-")|\(day)|\(sorted)"
    }
}

extension DateFormatter {
    static let dedupeKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Rappresentazione immutabile e `Sendable` usata da tutti i motori di analisi.
///
/// I motori non toccano mai SwiftData: lavorano su array di `DrawRecord`,
/// così sono testabili e possono girare fuori dal main actor.
struct DrawRecord: Hashable, Sendable, Identifiable {
    let date: Date
    let game: GameType
    let wheel: Wheel?
    /// Sempre ordinati in modo crescente.
    let numbers: [Int]
    let jolly: Int?
    let superstar: Int?

    init(date: Date, game: GameType, wheel: Wheel?, numbers: [Int], jolly: Int? = nil, superstar: Int? = nil) {
        self.date = date
        self.game = game
        self.wheel = wheel
        self.numbers = numbers.sorted()
        self.jolly = jolly
        self.superstar = superstar
    }

    var id: String {
        Draw.makeDedupeKey(date: date, game: game, wheel: wheel, numbers: numbers)
    }

    var numberSet: Set<Int> { Set(numbers) }

    var sum: Int { numbers.reduce(0, +) }

    var evenCount: Int { numbers.filter { $0 % 2 == 0 }.count }

    var oddCount: Int { numbers.count - evenCount }

    /// Numeri nella metà bassa (1–45).
    var lowCount: Int { numbers.filter { $0 <= 45 }.count }

    var highCount: Int { numbers.count - lowCount }

    /// Coppie di numeri consecutivi presenti nell'estrazione (es. 34 e 35).
    var consecutivePairsCount: Int {
        guard numbers.count > 1 else { return 0 }
        var count = 0
        for index in 1..<numbers.count where numbers[index] == numbers[index - 1] + 1 {
            count += 1
        }
        return count
    }

    var year: Int {
        Calendar.italian.component(.year, from: date)
    }

    var month: Int {
        Calendar.italian.component(.month, from: date)
    }
}

extension Calendar {
    /// Calendario con fuso orario italiano, usato per tutte le aggregazioni temporali.
    static let italian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        calendar.locale = Locale(identifier: "it_IT")
        return calendar
    }()
}
