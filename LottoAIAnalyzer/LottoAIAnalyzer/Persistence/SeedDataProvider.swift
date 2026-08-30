import Foundation

/// Fornisce i dati di esempio inclusi nell'app.
///
/// Servono solo a poter esplorare l'interfaccia prima di importare uno storico
/// reale: sono estrazioni **simulate**, generate in modo deterministico, e sono
/// etichettate come tali ovunque compaiano.
enum SeedDataProvider {

    /// Carica il file `estrazioni_esempio.csv` dal bundle, se presente.
    /// In assenza del file genera un campione simulato riproducibile.
    static func loadBundledSamples() throws -> [DrawRecord] {
        if let url = Bundle.main.url(forResource: "estrazioni_esempio", withExtension: "csv"),
           let data = try? Data(contentsOf: url) {
            return try CSVImporter.parse(data: data, defaultGame: .lotto)
        }
        return generateSimulatedHistory()
    }

    /// Storico simulato: 3 estrazioni a settimana per 4 anni su tutte le ruote,
    /// più il SuperEnalotto. Numeri generati con un RNG con seme fisso.
    static func generateSimulatedHistory(years: Int = 4, endingAt end: Date = Date()) -> [DrawRecord] {
        var generator = SeededRandom(seed: 2026_01_01)
        var records: [DrawRecord] = []
        guard let start = Calendar.italian.date(byAdding: .year, value: -years, to: end) else { return [] }

        var current = start
        while current <= end {
            let weekday = Calendar.italian.component(.weekday, from: current)
            // Martedì (3), giovedì (5) e sabato (7).
            if weekday == 3 || weekday == 5 || weekday == 7 {
                let date = DrawParser.normalizeToNoon(current)
                for wheel in Wheel.allCases {
                    records.append(DrawRecord(date: date,
                                              game: .lotto,
                                              wheel: wheel,
                                              numbers: draw(count: 5, generator: &generator)))
                }
                let numbers = draw(count: 6, generator: &generator)
                let extra = draw(count: 2, generator: &generator)
                records.append(DrawRecord(date: date,
                                          game: .superenalotto,
                                          wheel: nil,
                                          numbers: numbers,
                                          jolly: extra[0],
                                          superstar: extra[1]))
            }
            guard let next = Calendar.italian.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return records
    }

    private static func draw(count: Int, generator: inout SeededRandom) -> [Int] {
        var pool = Array(1...90)
        for position in 0..<count {
            let swapIndex = position + Int(generator.next() % UInt64(90 - position))
            pool.swapAt(position, swapIndex)
        }
        return Array(pool.prefix(count)).sorted()
    }
}
