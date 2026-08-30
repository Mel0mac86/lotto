import Foundation

/// Quante volte un numero è uscito insieme a un altro.
struct PartnerCount: Hashable, Identifiable, Sendable {
    let number: Int
    let count: Int
    /// Rapporto osservato/atteso: 1,0 = perfettamente in media.
    let lift: Double
    var id: Int { number }
}

/// Matrice simmetrica delle co-occorrenze fra numeri 1–90.
///
/// Memorizzata come vettore triangolare per restare compatta (4005 celle).
struct CoOccurrenceMatrix: Sendable {
    static let maxNumber = 90

    private(set) var counts: [Int]
    /// Numero di estrazioni da cui è stata costruita.
    private(set) var drawCount: Int
    /// Numeri estratti per estrazione (5 per il Lotto, 6 per il SuperEnalotto).
    private(set) var drawnPerDraw: Int

    init(drawCount: Int = 0, drawnPerDraw: Int = 5) {
        self.counts = Array(repeating: 0, count: Self.pairCount)
        self.drawCount = drawCount
        self.drawnPerDraw = drawnPerDraw
    }

    static let pairCount = maxNumber * (maxNumber - 1) / 2

    /// Indice lineare della coppia (a, b) con a < b, entrambi in 1...90.
    @inline(__always)
    static func index(_ a: Int, _ b: Int) -> Int {
        let low = min(a, b) - 1
        let high = max(a, b) - 1
        // Righe di lunghezza decrescente: offset della riga `low` + posizione.
        return low * (2 * maxNumber - low - 1) / 2 + (high - low - 1)
    }

    /// Coppia (a, b) corrispondente a un indice lineare.
    static func pair(at index: Int) -> (Int, Int) {
        var remaining = index
        var row = 0
        while row < maxNumber - 1 {
            let rowLength = maxNumber - row - 1
            if remaining < rowLength { break }
            remaining -= rowLength
            row += 1
        }
        return (row + 1, row + remaining + 2)
    }

    @inline(__always)
    func count(_ a: Int, _ b: Int) -> Int {
        guard a != b, (1...Self.maxNumber).contains(a), (1...Self.maxNumber).contains(b) else { return 0 }
        return counts[Self.index(a, b)]
    }

    mutating func add(_ numbers: [Int]) {
        guard numbers.count > 1 else { return }
        for i in 0..<(numbers.count - 1) {
            for j in (i + 1)..<numbers.count {
                let a = numbers[i], b = numbers[j]
                guard (1...Self.maxNumber).contains(a), (1...Self.maxNumber).contains(b), a != b else { continue }
                counts[Self.index(a, b)] += 1
            }
        }
        drawCount += 1
    }

    /// Co-occorrenze attese in caso di pura casualità.
    var expectedPairCount: Double {
        guard drawCount > 0, drawnPerDraw > 1 else { return 0 }
        let k = Double(drawnPerDraw)
        let n = Double(Self.maxNumber)
        // P(entrambi presenti) = C(k,2) / C(90,2)
        let probability = (k * (k - 1)) / (n * (n - 1))
        return probability * Double(drawCount)
    }

    /// Rapporto osservato/atteso per una coppia. 1.0 = perfettamente in media.
    func lift(_ a: Int, _ b: Int) -> Double {
        let expected = expectedPairCount
        guard expected > 0 else { return 0 }
        return Double(count(a, b)) / expected
    }

    /// Forza di co-occorrenza di un numero: media dei lift con tutti gli altri numeri.
    func strength(of number: Int) -> Double {
        var total = 0.0
        var partners = 0
        for other in 1...Self.maxNumber where other != number {
            total += lift(number, other)
            partners += 1
        }
        guard partners > 0 else { return 0 }
        return total / Double(partners)
    }

    /// I `limit` partner più ricorrenti di un numero, ordinati per conteggio.
    func topPartners(of number: Int, limit: Int = 5) -> [PartnerCount] {
        var partners: [PartnerCount] = []
        partners.reserveCapacity(Self.maxNumber - 1)
        for other in 1...Self.maxNumber where other != number {
            partners.append(PartnerCount(number: other,
                                         count: count(number, other),
                                         lift: lift(number, other)))
        }
        return Array(partners.sorted { $0.count > $1.count }.prefix(limit))
    }

    static func build(from draws: [DrawRecord], drawnPerDraw: Int) -> CoOccurrenceMatrix {
        var matrix = CoOccurrenceMatrix(drawCount: 0, drawnPerDraw: drawnPerDraw)
        for draw in draws { matrix.add(draw.numbers) }
        return matrix
    }
}
