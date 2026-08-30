import Foundation

/// Generatore pseudo-casuale deterministico (SplitMix64).
///
/// Serve per rendere riproducibili backtest e simulazioni: con lo stesso seme
/// l'algoritmo produce sempre le stesse combinazioni.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Double uniforme in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Estrae `count` indici distinti da pesi non negativi (campionamento senza reimmissione).
    mutating func weightedSample(weights: [Double], count: Int) -> [Int] {
        var remaining = weights
        var picked: [Int] = []
        picked.reserveCapacity(count)
        for _ in 0..<count {
            let total = remaining.reduce(0, +)
            guard total > 0 else { break }
            var threshold = nextUnit() * total
            var chosen = remaining.count - 1
            for (index, weight) in remaining.enumerated() {
                threshold -= weight
                if threshold <= 0 { chosen = index; break }
            }
            picked.append(chosen)
            remaining[chosen] = 0
        }
        return picked
    }
}
