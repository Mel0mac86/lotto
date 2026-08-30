import Foundation

/// Risultato dell'analisi di un terno.
struct TripleResult: Hashable, Identifiable, Sendable {
    let numbers: [Int]
    var score: Double
    var components: ScoreComponents
    /// Uscite della terna completa nel periodo.
    var jointCount: Int
    var expectedCount: Double
    var delay: Int
    /// Somma dei tre numeri.
    var sum: Int
    /// Uscite congiunte medie delle tre coppie interne.
    var averagePairCount: Double
    var reasons: [String] = []

    var id: String { numbers.map(String.init).joined(separator: "-") }
    var formatted: String { numbers.map { String(format: "%02d", $0) }.joined(separator: " – ") }
    var band: ScoreBand { ScoreBand(score: score) }
    var lift: Double { expectedCount > 0 ? Double(jointCount) / expectedCount : 0 }
    var evenCount: Int { numbers.filter { $0 % 2 == 0 }.count }
    var lowCount: Int { numbers.filter { $0 <= 45 }.count }
    var averageGap: Double {
        let sorted = numbers.sorted()
        guard sorted.count > 1 else { return 0 }
        return Double(sorted[sorted.count - 1] - sorted[0]) / Double(sorted.count - 1)
    }
}

/// **GENERA TERNO** — esplora le combinazioni di 3 numeri.
///
/// L'enumerazione completa è di 117.480 terne: viene eseguita per intero quando
/// `poolSize` è 90, altrimenti si limita ai numeri con indice statistico più alto
/// (utile per mantenere reattiva l'interfaccia sui dispositivi meno recenti).
enum TripleGenerator {

    static func topTriples(context: AnalysisContext,
                           limit: Int = 10,
                           poolSize: Int = 45) -> [TripleResult] {
        guard !context.isEmpty else { return [] }

        let pool: [Int]
        if poolSize >= 90 {
            pool = Array(context.game.numberRange)
        } else {
            pool = context.topNumbers(max(poolSize, limit + 5)).sorted()
        }
        guard pool.count >= 3 else { return [] }

        let expected = context.occurrences.expectedTripleCount
        var heap = TopKBuffer<TripleResult>(capacity: limit) { $0.score > $1.score }

        for i in 0..<(pool.count - 2) {
            for j in (i + 1)..<(pool.count - 1) {
                for k in (j + 1)..<pool.count {
                    let numbers = [pool[i], pool[j], pool[k]]
                    let evaluation = CombinationEngine.rawScore(numbers, context: context, weights: .triple)
                    let pairCounts = [context.occurrences.pairCount(numbers[0], numbers[1]),
                                      context.occurrences.pairCount(numbers[0], numbers[2]),
                                      context.occurrences.pairCount(numbers[1], numbers[2])]
                    let result = TripleResult(numbers: numbers,
                                              score: evaluation.score,
                                              components: evaluation.components,
                                              jointCount: context.occurrences.tripleCount(numbers[0], numbers[1], numbers[2]),
                                              expectedCount: expected,
                                              delay: context.occurrences.tripleDelay(numbers[0], numbers[1], numbers[2]),
                                              sum: numbers.reduce(0, +),
                                              averagePairCount: Double(pairCounts.reduce(0, +)) / 3.0)
                    heap.insert(result)
                }
            }
        }

        return heap.sortedElements().map { triple in
            var enriched = triple
            enriched.reasons = reasons(for: triple, context: context)
            return enriched
        }
    }

    static func reasons(for triple: TripleResult, context: AnalysisContext) -> [String] {
        var lines: [String] = []
        let stats = triple.numbers.map { context.stats(of: $0) }
        let frequencies = stats.map { String(format: "%02d (%d uscite)", $0.number, $0.occurrences) }
        lines.append("Frequenze individuali nel periodo: " + frequencies.joined(separator: ", ") + ".")
        lines.append(String(format: "Uscite congiunte delle coppie interne: %.1f in media.", triple.averagePairCount))

        if triple.jointCount > 0 {
            lines.append(String(format: "La terna completa è uscita %d volte (attese dal caso: %.2f); ritardo attuale %d estrazioni.",
                                triple.jointCount, triple.expectedCount, triple.delay))
        } else {
            lines.append(String(format: "La terna completa non è mai uscita nel periodo analizzato (attese dal caso: %.2f uscite).",
                                triple.expectedCount))
        }
        lines.append(String(format: "Distribuzione: %d pari / %d dispari, %d in 1–45, somma %d, distanza media %.1f.",
                            triple.evenCount, 3 - triple.evenCount, triple.lowCount, triple.sum, triple.averageGap))
        if let overdue = stats.max(by: { $0.currentDelay < $1.currentDelay }) {
            lines.append(String(format: "Ritardo più elevato del terno: %02d con %d estrazioni (massimo storico %d).",
                                overdue.number, overdue.currentDelay, overdue.maxDelay))
        }
        lines.append(Disclaimer.explainer)
        return lines
    }
}

/// Buffer dei migliori K elementi, per evitare di ordinare centinaia di migliaia di risultati.
struct TopKBuffer<Element> {
    private var storage: [Element] = []
    private let capacity: Int
    private let isHigherPriority: (Element, Element) -> Bool

    init(capacity: Int, isHigherPriority: @escaping (Element, Element) -> Bool) {
        self.capacity = max(capacity, 1)
        self.isHigherPriority = isHigherPriority
        storage.reserveCapacity(self.capacity + 1)
    }

    mutating func insert(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
            if storage.count == capacity { storage.sort(by: isHigherPriority) }
            return
        }
        // storage è ordinato: l'ultimo è il peggiore.
        guard let worst = storage.last, isHigherPriority(element, worst) else { return }
        storage.removeLast()
        let insertionIndex = storage.firstIndex { isHigherPriority(element, $0) } ?? storage.count
        storage.insert(element, at: insertionIndex)
    }

    func sortedElements() -> [Element] {
        storage.sorted(by: isHigherPriority)
    }
}
