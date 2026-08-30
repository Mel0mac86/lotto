import Foundation

/// Un pattern individuato nei dati storici.
struct DetectedPattern: Identifiable, Sendable {
    enum Category: String, Sendable, CaseIterable {
        case frequency = "Frequenze"
        case coOccurrence = "Co-occorrenze"
        case delay = "Ritardi"
        case distribution = "Distribuzioni"
        case temporal = "Pattern temporali"
        case cluster = "Cluster"
        case anomaly = "Anomalie"
    }

    let id = UUID()
    let category: Category
    let title: String
    let detail: String
    /// Test associato, quando il pattern è verificabile statisticamente.
    let test: TestResult?
    /// Valutazione onesta: il pattern è significativo o compatibile con il caso?
    let assessment: String
    let isNoteworthy: Bool
}

/// **TROVA PATTERN** — ricerca automatica di regolarità nei dati storici,
/// con distinzione esplicita fra ciò che è statisticamente significativo e ciò
/// che è compatibile con la normale variabilità casuale.
enum PatternFinder {

    static func analyze(context: AnalysisContext) -> [DetectedPattern] {
        guard context.drawCount >= 30 else {
            return [DetectedPattern(category: .anomaly,
                                    title: "Dati insufficienti",
                                    detail: "Servono almeno 30 estrazioni nel periodo selezionato per una ricerca di pattern attendibile.",
                                    test: nil,
                                    assessment: "Analisi non eseguita.",
                                    isNoteworthy: false)]
        }

        var patterns: [DetectedPattern] = []
        patterns.append(contentsOf: frequencyPatterns(context))
        patterns.append(contentsOf: coOccurrencePatterns(context))
        patterns.append(contentsOf: delayPatterns(context))
        patterns.append(contentsOf: distributionPatterns(context))
        patterns.append(contentsOf: temporalPatterns(context))
        patterns.append(contentsOf: clusterPatterns(context))
        patterns.append(multipleTestingWarning(count: patterns.count))
        return patterns
    }

    // MARK: - Frequenze

    private static func frequencyPatterns(_ context: AnalysisContext) -> [DetectedPattern] {
        let stats = context.statistics
        let observed = (1...90).map { Double(stats.numbers[$0]?.occurrences ?? 0) }
        let total = observed.reduce(0, +)
        let expected = Array(repeating: total / 90, count: 90)
        let test = StatisticalTests.chiSquareGoodnessOfFit(observed: observed,
                                                           expected: expected,
                                                           name: "Uniformità delle frequenze")

        var patterns = [DetectedPattern(
            category: .frequency,
            title: "Distribuzione complessiva delle frequenze",
            detail: "Chi quadro = \(String(format: "%.2f", test.statistic)) su \(test.degreesOfFreedom ?? 0) gradi di libertà.",
            test: test,
            assessment: test.interpretation,
            isNoteworthy: test.isSignificant)]

        // Singoli numeri fuori scala: test binomiale su ciascuno.
        let probability = Double(context.game.drawnCount) / 90
        let trials = context.drawCount
        var outliers: [(Int, TestResult)] = []
        for number in 1...90 {
            let occurrences = stats.numbers[number]?.occurrences ?? 0
            let result = StatisticalTests.binomialTest(successes: occurrences,
                                                       trials: trials,
                                                       probability: probability,
                                                       name: "Numero \(number)")
            if result.pValue < 0.01 { outliers.append((number, result)) }
        }
        if outliers.isEmpty {
            patterns.append(DetectedPattern(
                category: .frequency,
                title: "Nessun numero fuori scala",
                detail: "Nessun numero si discosta dall'atteso oltre la soglia dell'1%.",
                test: nil,
                assessment: "Il comportamento dei singoli numeri è compatibile con il caso.",
                isNoteworthy: false))
        } else {
            let list = outliers.map { String(format: "%02d", $0.0) }.joined(separator: ", ")
            // Con 90 test all'1% ci si attende circa 0,9 falsi positivi per puro caso.
            let expectedFalsePositives = 90 * 0.01
            patterns.append(DetectedPattern(
                category: .frequency,
                title: "Numeri con frequenza estrema",
                detail: "Numeri segnalati: \(list).",
                test: outliers.first?.1,
                assessment: "Sono stati eseguiti 90 test contemporaneamente: per puro caso ce ne si attendono circa \(String(format: "%.1f", expectedFalsePositives)) al livello dell'1%. Con \(outliers.count) segnalazioni il risultato \(outliers.count > 3 ? "merita attenzione ma resta descrittivo" : "è compatibile con la molteplicità dei test").",
                isNoteworthy: outliers.count > 3))
        }
        return patterns
    }

    // MARK: - Co-occorrenze

    private static func coOccurrencePatterns(_ context: AnalysisContext) -> [DetectedPattern] {
        let expected = context.occurrences.expectedPairCount
        guard expected > 0 else { return [] }
        var extremes: [(a: Int, b: Int, count: Int, p: Double)] = []
        let probability = pairProbability(drawn: context.game.drawnCount)

        for index in 0..<CoOccurrenceMatrix.pairCount {
            let (a, b) = CoOccurrenceMatrix.pair(at: index)
            let count = context.occurrences.pairCount(a, b)
            guard Double(count) > expected * 1.6, count >= 4 else { continue }
            let test = StatisticalTests.binomialTest(successes: count,
                                                     trials: context.drawCount,
                                                     probability: probability,
                                                     name: "Ambo \(a)-\(b)")
            if test.pValue < 0.001 { extremes.append((a, b, count, test.pValue)) }
        }

        let sorted = extremes.sorted { $0.count > $1.count }.prefix(5)
        guard !sorted.isEmpty else {
            return [DetectedPattern(category: .coOccurrence,
                                    title: "Co-occorrenze in linea con l'atteso",
                                    detail: String(format: "Uscite congiunte attese per coppia: %.2f. Nessuna coppia supera la soglia di significatività.", expected),
                                    test: nil,
                                    assessment: "Le co-occorrenze osservate sono compatibili con estrazioni indipendenti.",
                                    isNoteworthy: false)]
        }

        let list = sorted.map { String(format: "%02d–%02d (%d uscite)", $0.a, $0.b, $0.count) }.joined(separator: ", ")
        // 4005 coppie testate: alla soglia dello 0,1% ci si attendono ~4 falsi positivi.
        let expectedFalsePositives = Double(CoOccurrenceMatrix.pairCount) * 0.001
        return [DetectedPattern(
            category: .coOccurrence,
            title: "Coppie con ricorrenza superiore all'atteso",
            detail: list,
            test: nil,
            assessment: "Sono state testate tutte le \(CoOccurrenceMatrix.pairCount) coppie: al livello dello 0,1% ci si attendono circa \(String(format: "%.0f", expectedFalsePositives)) segnalazioni per puro caso. Con \(extremes.count) coppie segnalate il risultato \(Double(extremes.count) > expectedFalsePositives * 2 ? "è superiore all'atteso, pur restando descrittivo" : "è pienamente compatibile con il caso").",
            isNoteworthy: Double(extremes.count) > expectedFalsePositives * 2)]
    }

    // MARK: - Ritardi

    private static func delayPatterns(_ context: AnalysisContext) -> [DetectedPattern] {
        let items = (1...90).compactMap { context.statistics.numbers[$0] }
        guard let extreme = items.max(by: { $0.delayRatio < $1.delayRatio }) else { return [] }

        // In un processo geometrico il ritardo atteso è (1-p)/p con p = k/90.
        let probability = Double(context.game.drawnCount) / 90
        let theoreticalMean = (1 - probability) / probability
        let observedMean = items.map(\.averageDelay).reduce(0, +) / Double(items.count)

        var patterns: [DetectedPattern] = []
        patterns.append(DetectedPattern(
            category: .delay,
            title: "Ritardo medio osservato",
            detail: String(format: "Ritardo medio osservato: %.1f estrazioni. Valore teorico per un processo casuale: %.1f.", observedMean, theoreticalMean),
            test: nil,
            assessment: abs(observedMean - theoreticalMean) < theoreticalMean * 0.15
                ? "Il comportamento dei ritardi è quello atteso da estrazioni indipendenti."
                : "Il ritardo medio si discosta dal valore teorico: verificare la completezza dello storico importato.",
            isNoteworthy: abs(observedMean - theoreticalMean) >= theoreticalMean * 0.15))

        patterns.append(DetectedPattern(
            category: .delay,
            title: "Ritardo attuale più elevato",
            detail: String(format: "Il %02d manca da %d estrazioni, pari al %.0f%% del suo massimo storico (%d).",
                           extreme.number, extreme.currentDelay, extreme.delayRatio * 100, extreme.maxDelay),
            test: nil,
            assessment: Disclaimer.delay,
            isNoteworthy: false))
        return patterns
    }

    // MARK: - Distribuzioni

    private static func distributionPatterns(_ context: AnalysisContext) -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let drawn = context.game.drawnCount
        let totalNumbers = Double(context.drawCount * drawn)

        let evenTotal = context.draws.reduce(0) { $0 + $1.evenCount }
        let parity = StatisticalTests.binomialTest(successes: evenTotal,
                                                   trials: Int(totalNumbers),
                                                   probability: 0.5,
                                                   name: "Pari/dispari")
        patterns.append(DetectedPattern(
            category: .distribution,
            title: "Distribuzione pari/dispari",
            detail: String(format: "Pari: %d su %.0f numeri estratti (%.2f%%).", evenTotal, totalNumbers, Double(evenTotal) / totalNumbers * 100),
            test: parity,
            assessment: parity.interpretation,
            isNoteworthy: parity.isSignificant))

        let sums = context.statistics.sums
        if !sums.isEmpty {
            let mean = Double(sums.reduce(0, +)) / Double(sums.count)
            let theoretical = Double(drawn) * 45.5
            patterns.append(DetectedPattern(
                category: .distribution,
                title: "Somma delle combinazioni",
                detail: String(format: "Somma media osservata: %.1f. Somma media teorica: %.1f. Intervallo osservato: %d–%d.",
                               mean, theoretical, sums.min() ?? 0, sums.max() ?? 0),
                test: nil,
                assessment: abs(mean - theoretical) < Double(drawn) * 1.5
                    ? "La distribuzione delle somme è quella attesa da estrazioni casuali."
                    : "La somma media si discosta dal valore teorico: possibile storico parziale o non uniforme.",
                isNoteworthy: abs(mean - theoretical) >= Double(drawn) * 1.5))
        }

        let consecutiveRate = Double(context.statistics.drawsWithConsecutives) / Double(max(context.drawCount, 1))
        let theoreticalConsecutive = theoreticalConsecutiveProbability(drawn: drawn)
        patterns.append(DetectedPattern(
            category: .distribution,
            title: "Numeri consecutivi",
            detail: String(format: "Estrazioni con almeno una coppia consecutiva: %.1f%% (atteso teorico %.1f%%).",
                           consecutiveRate * 100, theoreticalConsecutive * 100),
            test: StatisticalTests.binomialTest(successes: context.statistics.drawsWithConsecutives,
                                                trials: context.drawCount,
                                                probability: theoreticalConsecutive,
                                                name: "Coppie consecutive"),
            assessment: "Le coppie consecutive sono molto più comuni di quanto l'intuizione suggerisca: è un effetto noto della combinatoria, non un pattern.",
            isNoteworthy: false))
        return patterns
    }

    // MARK: - Pattern temporali

    private static func temporalPatterns(_ context: AnalysisContext) -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        let byMonth = context.statistics.byMonth
        guard byMonth.count >= 6 else { return patterns }

        let monthlyTotals = (1...12).map { month -> Double in
            Double(byMonth[month]?.values.reduce(0, +) ?? 0)
        }
        let total = monthlyTotals.reduce(0, +)
        guard total > 0 else { return patterns }

        // Il numero di estrazioni per mese non è uniforme: si normalizza sui giorni disponibili.
        var drawsPerMonth = [Int: Int]()
        for draw in context.draws { drawsPerMonth[draw.month, default: 0] += 1 }
        let expectedByMonth = (1...12).map { month -> Double in
            Double(drawsPerMonth[month] ?? 0) * Double(context.game.drawnCount)
        }
        guard expectedByMonth.reduce(0, +) > 0 else { return patterns }

        let test = StatisticalTests.chiSquareGoodnessOfFit(observed: monthlyTotals,
                                                           expected: expectedByMonth,
                                                           name: "Stagionalità mensile")
        patterns.append(DetectedPattern(
            category: .temporal,
            title: "Stagionalità delle uscite",
            detail: "Confronto fra uscite mensili osservate e attese in base al numero di estrazioni per mese.",
            test: test,
            assessment: test.isSignificant
                ? "Emerge uno scostamento mensile: prima di interpretarlo verificare che lo storico copra tutti i mesi in modo omogeneo."
                : "Nessuna stagionalità rilevabile: le uscite mensili riflettono soltanto quante estrazioni ci sono state in ciascun mese.",
            isNoteworthy: test.isSignificant))
        return patterns
    }

    // MARK: - Cluster

    private static func clusterPatterns(_ context: AnalysisContext) -> [DetectedPattern] {
        let features = MLFeatureBuilder.numberFeatures(context: context)
        guard features.count >= 10 else { return [] }
        let clusters = KMeans.fit(points: features.map(\.vector), clusters: 3, seed: 42)
        var grouped = [Int: [Int]]()
        for (index, assignment) in clusters.assignments.enumerated() {
            grouped[assignment, default: []].append(features[index].number)
        }
        let description = grouped.sorted { $0.key < $1.key }.map { key, numbers in
            "Gruppo \(key + 1): \(numbers.count) numeri (\(numbers.prefix(8).map { String(format: "%02d", $0) }.joined(separator: ", "))\(numbers.count > 8 ? "…" : ""))"
        }.joined(separator: "\n")

        return [DetectedPattern(
            category: .cluster,
            title: "Raggruppamento dei numeri per profilo statistico",
            detail: description,
            test: nil,
            assessment: "Il clustering descrive come i numeri si somigliano per frequenza, ritardo e trend nel periodo osservato. Raggruppamenti di questo tipo emergono anche da dati puramente casuali e non indicano un comportamento futuro.",
            isNoteworthy: false)]
    }

    private static func multipleTestingWarning(count: Int) -> DetectedPattern {
        DetectedPattern(
            category: .anomaly,
            title: "Nota sulla molteplicità dei test",
            detail: "In questa analisi sono stati eseguiti migliaia di confronti (90 numeri, 4.005 coppie, distribuzioni, stagionalità).",
            test: nil,
            assessment: "Quando si eseguono molti test contemporaneamente, alcuni risultati \"significativi\" compaiono per puro caso. Ogni pattern qui elencato va letto come descrizione del passato, mai come indicazione sul futuro.",
            isNoteworthy: false)
    }

    // MARK: - Helper

    private static func pairProbability(drawn: Int) -> Double {
        let k = Double(drawn)
        return (k * (k - 1)) / (90.0 * 89.0)
    }

    /// Probabilità che una combinazione di `drawn` numeri su 90 contenga almeno una coppia consecutiva.
    private static func theoreticalConsecutiveProbability(drawn: Int) -> Double {
        // Combinazioni senza numeri consecutivi: C(90 - k + 1, k).
        let n = 90, k = drawn
        guard k >= 2, n - k + 1 >= k else { return 0 }
        let withoutConsecutive = binomial(n - k + 1, k)
        let total = binomial(n, k)
        guard total > 0 else { return 0 }
        return 1 - withoutConsecutive / total
    }

    private static func binomial(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        var result = 1.0
        for index in 0..<k {
            result *= Double(n - index) / Double(index + 1)
        }
        return result
    }
}
