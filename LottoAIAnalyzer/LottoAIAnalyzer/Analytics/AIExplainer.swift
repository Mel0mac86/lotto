import Foundation

/// Un blocco della spiegazione generata.
struct ExplanationSection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let icon: String
    let body: String
}

/// **AI EXPLAINER** — traduce in italiano corrente il perché di una combinazione.
///
/// Funziona interamente sul dispositivo: nessun dato lascia l'iPhone.
/// Il linguaggio è deliberatamente descrittivo ("ha avuto una frequenza superiore
/// alla media") e mai predittivo ("uscirà").
enum AIExplainer {

    static func explain(combination: ScoredCombination,
                        context: AnalysisContext,
                        strategy: GenerationStrategy? = nil) -> [ExplanationSection] {
        var sections: [ExplanationSection] = []

        sections.append(ExplanationSection(
            title: "In sintesi",
            icon: "text.bubble",
            body: summary(combination: combination, context: context, strategy: strategy)))

        sections.append(ExplanationSection(
            title: "Numero per numero",
            icon: "list.number",
            body: combination.numbers.map { numberLine($0, context: context) }.joined(separator: "\n")))

        if combination.numbers.count >= 2 {
            sections.append(ExplanationSection(
                title: "Come si comportano insieme",
                icon: "link",
                body: coOccurrenceLines(combination.numbers, context: context)))
        }

        sections.append(ExplanationSection(
            title: "Equilibrio della combinazione",
            icon: "scalemass",
            body: balanceLine(combination: combination, context: context)))

        sections.append(ExplanationSection(
            title: "Cosa significa (e cosa non significa)",
            icon: "exclamationmark.triangle",
            body: "\(Disclaimer.score)\n\n\(Disclaimer.explainer)"))

        return sections
    }

    // MARK: - Blocchi

    private static func summary(combination: ScoredCombination,
                                context: AnalysisContext,
                                strategy: GenerationStrategy?) -> String {
        var text = "Su \(context.drawCount) estrazioni analizzate (\(context.filter.summary)), "
        text += "questa combinazione ottiene un indice statistico di \(Int(combination.score.rounded()))/100"
        text += " (\(combination.band.label.lowercased()))."
        if let strategy {
            text += " La generazione ha seguito la strategia «\(strategy.displayName)»: \(strategy.explanation.lowercased())"
        }
        let dominant = combination.components.labelledValues.max { $0.value < $1.value }
        if let dominant {
            text += " Il criterio che pesa di più è «\(dominant.label.lowercased())» (\(Int(dominant.value.rounded()))/100)."
        }
        return text
    }

    private static func numberLine(_ number: Int, context: AnalysisContext) -> String {
        let stats = context.stats(of: number)
        let score = context.score(of: number)
        var descriptors: [String] = []

        if stats.frequencyRatio > 1.08 {
            descriptors.append(String(format: "frequenza superiore alla media del %.0f%%", (stats.frequencyRatio - 1) * 100))
        } else if stats.frequencyRatio < 0.92 {
            descriptors.append(String(format: "frequenza inferiore alla media del %.0f%%", (1 - stats.frequencyRatio) * 100))
        } else {
            descriptors.append("frequenza in linea con la media")
        }

        if stats.isOverdue {
            descriptors.append(String(format: "ritardo elevato (%d estrazioni contro una media di %.0f)", stats.currentDelay, stats.averageDelay))
        } else {
            descriptors.append("ritardo di \(stats.currentDelay) estrazioni")
        }

        if stats.isHot {
            descriptors.append("in crescita nel periodo recente")
        } else if stats.isCold {
            descriptors.append("in calo nel periodo recente")
        }

        return String(format: "• %02d (indice %d): ", number, Int(score.rounded())) + descriptors.joined(separator: ", ") + "."
    }

    private static func coOccurrenceLines(_ numbers: [Int], context: AnalysisContext) -> String {
        var pairs: [(a: Int, b: Int, count: Int, lift: Double)] = []
        for i in 0..<(numbers.count - 1) {
            for j in (i + 1)..<numbers.count {
                pairs.append((numbers[i], numbers[j],
                              context.occurrences.pairCount(numbers[i], numbers[j]),
                              context.occurrences.pairLift(numbers[i], numbers[j])))
            }
        }
        let sorted = pairs.sorted { $0.lift > $1.lift }
        let lines = sorted.prefix(4).map { pair -> String in
            let comparison: String
            if pair.lift > 1.1 {
                comparison = String(format: "il %.0f%% in più dell'atteso", (pair.lift - 1) * 100)
            } else if pair.lift < 0.9 {
                comparison = String(format: "il %.0f%% in meno dell'atteso", (1 - pair.lift) * 100)
            } else {
                comparison = "in linea con l'atteso"
            }
            return String(format: "• %02d–%02d: %d uscite congiunte, %@.", pair.a, pair.b, pair.count, comparison)
        }
        var text = lines.joined(separator: "\n")
        let averageLift = pairs.isEmpty ? 0 : pairs.map(\.lift).reduce(0, +) / Double(pairs.count)
        text += String(format: "\n\nRicorrenza media delle coppie interne: %.2f volte l'atteso casuale.", averageLift)
        return text
    }

    private static func balanceLine(combination: ScoredCombination, context: AnalysisContext) -> String {
        let expectedSum = context.sumMean / Double(context.game.drawnCount) * Double(combination.numbers.count)
        var text = String(format: "Pari %d · dispari %d · fascia 1–45: %d · fascia 46–90: %d · somma %d (media storica %.0f).",
                          combination.evenCount, combination.oddCount,
                          combination.lowCount, combination.highCount,
                          combination.sum, expectedSum)
        let decades = combination.decadeDistribution.count
        text += "\nI numeri coprono \(decades) decine diverse, con una distanza media di \(String(format: "%.1f", combination.averageGap)) fra numeri consecutivi della combinazione."
        if combination.components.balance >= 70 {
            text += "\nNel complesso la combinazione è distribuita come lo sono tipicamente le estrazioni storiche."
        } else {
            text += "\nNel complesso la combinazione è distribuita in modo meno tipico rispetto allo storico: questo abbassa la componente di equilibrio dell'indice."
        }
        return text
    }

    // MARK: - Spiegazione di un singolo numero

    static func explainNumber(_ number: Int, context: AnalysisContext) -> String {
        let stats = context.stats(of: number)
        let partners = CoOccurrenceMatrix.build(from: context.draws, drawnPerDraw: context.game.drawnCount)
            .topPartners(of: number, limit: 3)
        var text = numberLine(number, context: context)
        if let lastSeen = stats.lastSeen {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "it_IT")
            formatter.dateStyle = .medium
            text += "\nUltima uscita: \(formatter.string(from: lastSeen))."
        }
        if !partners.isEmpty {
            let list = partners.map { String(format: "%02d (%d volte)", $0.number, $0.count) }.joined(separator: ", ")
            text += "\nNumeri con cui è uscito più spesso: \(list)."
        }
        text += "\n\n\(Disclaimer.explainer)"
        return text
    }
}
