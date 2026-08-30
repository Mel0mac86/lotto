import Foundation

/// Costruisce i `ReportDocument` a partire dai risultati delle analisi.
enum ReportBuilder {

    static func analysisReport(context: AnalysisContext, topCount: Int = 30) -> ReportDocument {
        var document = ReportDocument(title: "Analisi statistica",
                                      scope: context.filter.summary,
                                      method: "Statistical Number Score con pesi \(weightsDescription(context.weights))")

        document.summaryLines = [
            "Estrazioni analizzate: \(context.drawCount)",
            "Periodo: \(dateRange(context))",
            "Somma media delle combinazioni: \(Theme.decimal(context.sumMean))"
        ]

        let ranked = context.rankedNumbers
        document.tables.append(ReportTable(
            title: "Indice statistico per numero (primi \(topCount))",
            headers: ["Numero", "Uscite", "Frequenza %", "Ritardo", "Rit. medio", "Rit. max", "Percentile", "Indice"],
            rows: ranked.prefix(topCount).map { item in
                [Theme.number(item.number),
                 "\(item.statistics.occurrences)",
                 Theme.decimal(item.statistics.frequency * 100, digits: 2),
                 "\(item.statistics.currentDelay)",
                 Theme.decimal(item.statistics.averageDelay),
                 "\(item.statistics.maxDelay)",
                 Theme.decimal(item.statistics.frequencyPercentile, digits: 0),
                 "\(Int(item.score.rounded()))"]
            },
            note: "L'indice statistico descrive il comportamento passato del numero. " + Disclaimer.score))

        document.tables.append(ReportTable(
            title: "Distribuzioni",
            headers: ["Categoria", "Valore", "Conteggio"],
            rows: distributionRows(context),
            note: nil))

        return document
    }

    static func combinationsReport(results: [GeneratedResult], context: AnalysisContext) -> ReportDocument {
        var document = ReportDocument(title: "Combinazioni generate",
                                      scope: context.filter.summary,
                                      method: results.first.map { "Strategia \($0.strategy.displayName)" } ?? "—")
        document.summaryLines = ["Combinazioni generate: \(results.count)",
                                 "Estrazioni analizzate: \(context.drawCount)"]

        document.tables.append(ReportTable(
            title: "Combinazioni",
            headers: ["#", "Numeri", "Indice", "Pari", "Dispari", "1–45", "46–90", "Somma"],
            rows: results.enumerated().map { index, result in
                let combination = result.combination
                return ["\(index + 1)",
                        combination.formatted,
                        "\(Int(combination.score.rounded()))",
                        "\(combination.evenCount)",
                        "\(combination.oddCount)",
                        "\(combination.lowCount)",
                        "\(combination.highCount)",
                        "\(combination.sum)"]
            },
            note: Disclaimer.score))

        for (index, result) in results.enumerated() {
            document.tables.append(ReportTable(
                title: "Motivazioni — combinazione \(index + 1) (\(result.combination.formatted))",
                headers: ["Motivazione"],
                rows: result.combination.reasons.map { [$0] },
                note: nil))
        }
        return document
    }

    static func pairsReport(pairs: [PairResult], context: AnalysisContext) -> ReportDocument {
        var document = ReportDocument(title: "Top ambi",
                                      scope: context.filter.summary,
                                      method: "Analisi di tutte le 4.005 coppie con scoring co-occorrenza")
        document.summaryLines = ["Estrazioni analizzate: \(context.drawCount)"]
        document.tables.append(ReportTable(
            title: "Ambi con indice statistico più alto",
            headers: ["#", "Ambo", "Uscite congiunte", "Attese", "Rapporto", "Ritardo", "Recenti", "Indice"],
            rows: pairs.enumerated().map { index, pair in
                ["\(index + 1)", pair.formatted, "\(pair.jointCount)",
                 Theme.decimal(pair.expectedCount, digits: 2),
                 Theme.decimal(pair.lift, digits: 2),
                 "\(pair.delay)", "\(pair.recentCount)",
                 "\(Int(pair.score.rounded()))"]
            },
            note: Disclaimer.score))
        return document
    }

    static func triplesReport(triples: [TripleResult], context: AnalysisContext) -> ReportDocument {
        var document = ReportDocument(title: "Top terni",
                                      scope: context.filter.summary,
                                      method: "Analisi delle combinazioni di tre numeri")
        document.tables.append(ReportTable(
            title: "Terni con indice statistico più alto",
            headers: ["#", "Terno", "Uscite terna", "Attese", "Coppie interne", "Ritardo", "Somma", "Indice"],
            rows: triples.enumerated().map { index, triple in
                ["\(index + 1)", triple.formatted, "\(triple.jointCount)",
                 Theme.decimal(triple.expectedCount, digits: 3),
                 Theme.decimal(triple.averagePairCount),
                 "\(triple.delay)", "\(triple.sum)",
                 "\(Int(triple.score.rounded()))"]
            },
            note: Disclaimer.score))
        return document
    }

    static func backtestReport(result: BacktestResult, validation: ValidationReport?) -> ReportDocument {
        let configuration = result.configuration
        var document = ReportDocument(
            title: "Backtest \(configuration.kind.displayName)",
            scope: "\(configuration.game.displayName)\(configuration.wheel.map { " · \($0.displayName)" } ?? "") · \(Theme.dateFormatter.string(from: configuration.startDate)) → \(Theme.dateFormatter.string(from: configuration.endDate))",
            method: "Walk-forward, finestra storica \(configuration.lookback.displayName.lowercased()), \(configuration.playsPerDraw) giocate per estrazione, posta \(Theme.currency(configuration.stakePerPlay))")

        document.summaryLines = [
            "Estrazioni simulate: \(result.drawsEvaluated)",
            "Giocate totali: \(result.strategy.totalPlays)",
            "Costo teorico: \(Theme.currency(result.strategy.totalCost))",
            "Vincite teoriche: \(Theme.currency(result.strategy.totalWinnings))",
            "Saldo teorico: \(Theme.currency(result.strategy.net))",
            "ROI teorico: \(Theme.percent(result.strategy.roi))",
            "Baseline casuale — ROI: \(Theme.percent(result.baseline.roi))",
            result.significance.interpretation,
            result.verdict
        ]

        let keys = Set(result.strategy.hitDistribution.keys).union(result.baseline.hitDistribution.keys).sorted()
        document.tables.append(ReportTable(
            title: "Distribuzione dei risultati",
            headers: ["Numeri indovinati", "Strategia", "Baseline casuale"],
            rows: keys.map { ["\($0)", "\(result.strategy.hits($0))", "\(result.baseline.hits($0))"] },
            note: nil))

        document.tables.append(ReportTable(
            title: "Dettaglio estrazioni",
            headers: ["Data", "Estrazione", "Giocate", "Miglior risultato", "Costo", "Vincita"],
            rows: result.steps.map { step in
                [Theme.shortDateFormatter.string(from: step.date),
                 step.drawnNumbers.map { Theme.number($0) }.joined(separator: " "),
                 step.plays.map { $0.map { Theme.number($0) }.joined(separator: "-") }.joined(separator: " | "),
                 "\(step.bestMatch)",
                 Theme.currency(step.cost),
                 Theme.currency(step.winnings)]
            },
            note: Disclaimer.backtest))

        if let validation {
            document.tables.append(ReportTable(
                title: "Sistema di validazione",
                headers: ["Controllo", "Esito", "Dettaglio"],
                rows: validation.checks.map { [$0.name, $0.passed ? "superato" : "non superato", $0.detail] },
                note: validation.verdict))
        }
        return document
    }

    // MARK: - Helper

    private static func distributionRows(_ context: AnalysisContext) -> [[String]] {
        var rows: [[String]] = []
        for (even, count) in context.statistics.evenDistribution.sorted(by: { $0.key < $1.key }) {
            rows.append(["Pari per estrazione", "\(even)", "\(count)"])
        }
        for (low, count) in context.statistics.lowDistribution.sorted(by: { $0.key < $1.key }) {
            rows.append(["Numeri 1–45 per estrazione", "\(low)", "\(count)"])
        }
        for decade in 0...8 {
            rows.append(["Decina", "\(decade * 10 + 1)–\(decade * 10 + 10)", "\(context.statistics.decadeDistribution[decade] ?? 0)"])
        }
        for unit in 0...9 {
            rows.append(["Cifra delle unità", "\(unit)", "\(context.statistics.unitDistribution[unit] ?? 0)"])
        }
        rows.append(["Estrazioni con numeri consecutivi", "—", "\(context.statistics.drawsWithConsecutives)"])
        return rows
    }

    private static func dateRange(_ context: AnalysisContext) -> String {
        guard let first = context.statistics.firstDate, let last = context.statistics.lastDate else { return "—" }
        return "\(Theme.dateFormatter.string(from: first)) → \(Theme.dateFormatter.string(from: last))"
    }

    private static func weightsDescription(_ weights: ScoringWeights) -> String {
        let normalized = weights.normalized()
        return "frequenza \(Theme.decimal(normalized.frequency * 100, digits: 0))%, "
            + "recenza \(Theme.decimal(normalized.recency * 100, digits: 0))%, "
            + "ritardo \(Theme.decimal(normalized.delay * 100, digits: 0))%, "
            + "trend \(Theme.decimal(normalized.trend * 100, digits: 0))%, "
            + "co-occorrenza \(Theme.decimal(normalized.coOccurrence * 100, digits: 0))%, "
            + "stabilità \(Theme.decimal(normalized.stability * 100, digits: 0))%"
    }
}
