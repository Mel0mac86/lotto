import Foundation

/// Indice delle uscite di coppie e terne: quante volte sono usciti insieme
/// e in quale estrazione è avvenuta l'ultima uscita congiunta.
struct SetOccurrenceIndex: Sendable {
    /// Conteggi delle coppie (vettore triangolare, stesso layout di `CoOccurrenceMatrix`).
    private(set) var pairCounts: [Int32]
    /// Indice dell'ultima estrazione in cui la coppia è uscita (-1 = mai).
    private(set) var pairLastIndex: [Int32]
    /// Terne osservate: chiave compatta -> (conteggio, ultimo indice).
    private(set) var tripleCounts: [Int: (count: Int32, lastIndex: Int32)]

    private(set) var drawCount: Int
    private(set) var drawnPerDraw: Int

    init(draws: [DrawRecord], drawnPerDraw: Int) {
        pairCounts = Array(repeating: 0, count: CoOccurrenceMatrix.pairCount)
        pairLastIndex = Array(repeating: -1, count: CoOccurrenceMatrix.pairCount)
        tripleCounts = [:]
        tripleCounts.reserveCapacity(draws.count * 10)
        drawCount = draws.count
        self.drawnPerDraw = drawnPerDraw

        for (drawIndex, draw) in draws.enumerated() {
            let numbers = draw.numbers
            guard numbers.count >= 2 else { continue }
            for i in 0..<(numbers.count - 1) {
                for j in (i + 1)..<numbers.count {
                    let index = CoOccurrenceMatrix.index(numbers[i], numbers[j])
                    pairCounts[index] += 1
                    pairLastIndex[index] = Int32(drawIndex)
                }
            }
            guard numbers.count >= 3 else { continue }
            for i in 0..<(numbers.count - 2) {
                for j in (i + 1)..<(numbers.count - 1) {
                    for k in (j + 1)..<numbers.count {
                        let key = Self.tripleKey(numbers[i], numbers[j], numbers[k])
                        let current = tripleCounts[key] ?? (0, -1)
                        tripleCounts[key] = (current.count + 1, Int32(drawIndex))
                    }
                }
            }
        }
    }

    /// Chiave compatta per una terna ordinata (1...90).
    @inline(__always)
    static func tripleKey(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let sorted = [a, b, c].sorted()
        return sorted[0] * 91 * 91 + sorted[1] * 91 + sorted[2]
    }

    func pairCount(_ a: Int, _ b: Int) -> Int {
        guard a != b else { return 0 }
        return Int(pairCounts[CoOccurrenceMatrix.index(a, b)])
    }

    /// Estrazioni trascorse dall'ultima uscita congiunta della coppia.
    /// Restituisce `drawCount` se non sono mai uscite insieme.
    func pairDelay(_ a: Int, _ b: Int) -> Int {
        guard a != b else { return drawCount }
        let last = pairLastIndex[CoOccurrenceMatrix.index(a, b)]
        guard last >= 0 else { return drawCount }
        return drawCount - 1 - Int(last)
    }

    func tripleCount(_ a: Int, _ b: Int, _ c: Int) -> Int {
        Int(tripleCounts[Self.tripleKey(a, b, c)]?.count ?? 0)
    }

    func tripleDelay(_ a: Int, _ b: Int, _ c: Int) -> Int {
        guard let entry = tripleCounts[Self.tripleKey(a, b, c)], entry.lastIndex >= 0 else { return drawCount }
        return drawCount - 1 - Int(entry.lastIndex)
    }

    /// Uscite attese di una coppia in caso di pura casualità.
    var expectedPairCount: Double {
        guard drawCount > 0, drawnPerDraw >= 2 else { return 0 }
        let k = Double(drawnPerDraw), n = 90.0
        return (k * (k - 1)) / (n * (n - 1)) * Double(drawCount)
    }

    /// Uscite attese di una terna in caso di pura casualità.
    var expectedTripleCount: Double {
        guard drawCount > 0, drawnPerDraw >= 3 else { return 0 }
        let k = Double(drawnPerDraw), n = 90.0
        return (k * (k - 1) * (k - 2)) / (n * (n - 1) * (n - 2)) * Double(drawCount)
    }

    func pairLift(_ a: Int, _ b: Int) -> Double {
        let expected = expectedPairCount
        guard expected > 0 else { return 0 }
        return Double(pairCount(a, b)) / expected
    }

    func tripleLift(_ a: Int, _ b: Int, _ c: Int) -> Double {
        let expected = expectedTripleCount
        guard expected > 0 else { return 0 }
        return Double(tripleCount(a, b, c)) / expected
    }
}
