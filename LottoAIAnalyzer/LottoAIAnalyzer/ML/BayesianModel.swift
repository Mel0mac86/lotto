import Foundation

/// Stima bayesiana della probabilità di uscita di ciascun numero.
///
/// Usa un prior Beta(α, β) centrato sul valore teorico k/90 e lo aggiorna con le
/// uscite osservate. Il risultato tipico su dati reali è un posteriore molto
/// vicino al prior: è la dimostrazione quantitativa che lo storico non sposta
/// la probabilità di uscita.
struct BayesianModel: Sendable {

    struct Posterior: Identifiable, Sendable {
        let number: Int
        let mean: Double
        let lowerBound: Double
        let upperBound: Double
        let theoretical: Double

        var id: Int { number }
        /// L'intervallo di credibilità al 95% contiene il valore teorico?
        var containsTheoretical: Bool { theoretical >= lowerBound && theoretical <= upperBound }
        var deviationPercent: Double { theoretical > 0 ? (mean - theoretical) / theoretical * 100 : 0 }
    }

    /// Forza del prior espressa in "estrazioni equivalenti".
    var priorStrength: Double = 200

    func posteriors(context: AnalysisContext) -> [Posterior] {
        let trials = Double(context.drawCount)
        guard trials > 0 else { return [] }
        let theoretical = Double(context.game.drawnCount) / 90
        let alphaPrior = theoretical * priorStrength
        let betaPrior = (1 - theoretical) * priorStrength

        return context.game.numberRange.map { number in
            let successes = Double(context.stats(of: number).occurrences)
            let alpha = alphaPrior + successes
            let beta = betaPrior + (trials - successes)
            let mean = alpha / (alpha + beta)
            // Approssimazione normale dell'intervallo di credibilità al 95%.
            let variance = alpha * beta / (pow(alpha + beta, 2) * (alpha + beta + 1))
            let sigma = variance.squareRoot()
            return Posterior(number: number,
                             mean: mean,
                             lowerBound: max(mean - 1.96 * sigma, 0),
                             upperBound: min(mean + 1.96 * sigma, 1),
                             theoretical: theoretical)
        }
    }

    /// Sintesi in italiano dell'esito bayesiano.
    func summary(for posteriors: [Posterior]) -> String {
        guard !posteriors.isEmpty else { return "Dati insufficienti." }
        let outside = posteriors.filter { !$0.containsTheoretical }
        let expectedOutside = Double(posteriors.count) * 0.05
        if outside.isEmpty {
            return "Per tutti i 90 numeri l'intervallo di credibilità al 95% contiene la probabilità teorica: i dati storici sono pienamente compatibili con l'equiprobabilità."
        }
        let list = outside.prefix(6).map { String(format: "%02d", $0.number) }.joined(separator: ", ")
        return String(format: "%d numeri su %d hanno un intervallo di credibilità che non contiene la probabilità teorica (%@). Con intervalli al 95%%, per puro caso ce ne si attendono circa %.1f: il risultato è %@.",
                      outside.count, posteriors.count, list, expectedOutside,
                      Double(outside.count) <= expectedOutside * 2 ? "compatibile con la casualità" : "superiore all'atteso, ma resta una descrizione del passato")
    }
}
