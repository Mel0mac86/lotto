import Foundation

/// Esito di un test statistico, con interpretazione in italiano.
struct TestResult: Hashable, Sendable, Identifiable {
    let name: String
    let statistic: Double
    let degreesOfFreedom: Int?
    let pValue: Double
    let interpretation: String

    var id: String { name }
    /// Soglia convenzionale del 5%.
    var isSignificant: Bool { pValue < 0.05 }
}

/// Test di significatività usati dal sistema di validazione e dalla ricerca di pattern.
enum StatisticalTests {

    // MARK: - Chi quadro

    /// Test di bontà di adattamento: le frequenze osservate sono compatibili con quelle attese?
    static func chiSquareGoodnessOfFit(observed: [Double], expected: [Double], name: String) -> TestResult {
        precondition(observed.count == expected.count, "Vettori di lunghezza diversa")
        var statistic = 0.0
        var usedCells = 0
        for (index, expectedValue) in expected.enumerated() where expectedValue > 0 {
            let difference = observed[index] - expectedValue
            statistic += difference * difference / expectedValue
            usedCells += 1
        }
        let degrees = max(usedCells - 1, 1)
        let p = chiSquarePValue(statistic: statistic, degreesOfFreedom: degrees)
        let interpretation = p < 0.05
            ? "Le frequenze osservate si discostano dal modello casuale in misura statisticamente significativa (p = \(format(p)))."
            : "Le frequenze osservate sono compatibili con un processo casuale (p = \(format(p)))."
        return TestResult(name: name, statistic: statistic, degreesOfFreedom: degrees,
                          pValue: p, interpretation: interpretation)
    }

    /// p-value della distribuzione chi quadro: P(X > statistic).
    static func chiSquarePValue(statistic: Double, degreesOfFreedom: Int) -> Double {
        guard statistic > 0, degreesOfFreedom > 0 else { return 1 }
        return 1 - regularizedLowerGamma(a: Double(degreesOfFreedom) / 2, x: statistic / 2)
    }

    // MARK: - Test binomiale (approssimazione normale)

    /// Verifica se `successes` su `trials` si discosta dalla probabilità attesa.
    static func binomialTest(successes: Int, trials: Int, probability: Double, name: String) -> TestResult {
        guard trials > 0, probability > 0, probability < 1 else {
            return TestResult(name: name, statistic: 0, degreesOfFreedom: nil, pValue: 1,
                              interpretation: "Dati insufficienti per il test.")
        }
        let mean = Double(trials) * probability
        let sigma = (Double(trials) * probability * (1 - probability)).squareRoot()
        guard sigma > 0 else {
            return TestResult(name: name, statistic: 0, degreesOfFreedom: nil, pValue: 1,
                              interpretation: "Varianza nulla: test non applicabile.")
        }
        // Correzione di continuità.
        let difference = abs(Double(successes) - mean) - 0.5
        let z = max(difference, 0) / sigma
        let p = 2 * (1 - standardNormalCDF(z))
        let direction = Double(successes) > mean ? "superiore" : "inferiore"
        let interpretation = p < 0.05
            ? "Il risultato osservato è \(direction) all'atteso in modo statisticamente significativo (z = \(format(z)), p = \(format(p)))."
            : "Il risultato osservato è compatibile con l'atteso casuale (z = \(format(z)), p = \(format(p)))."
        return TestResult(name: name, statistic: z, degreesOfFreedom: nil, pValue: p, interpretation: interpretation)
    }

    /// Confronto fra due proporzioni (strategia contro baseline casuale).
    static func twoProportionZTest(successesA: Int, trialsA: Int,
                                   successesB: Int, trialsB: Int,
                                   name: String) -> TestResult {
        guard trialsA > 0, trialsB > 0 else {
            return TestResult(name: name, statistic: 0, degreesOfFreedom: nil, pValue: 1,
                              interpretation: "Dati insufficienti per il confronto.")
        }
        let pA = Double(successesA) / Double(trialsA)
        let pB = Double(successesB) / Double(trialsB)
        let pooled = Double(successesA + successesB) / Double(trialsA + trialsB)
        let standardError = (pooled * (1 - pooled) * (1.0 / Double(trialsA) + 1.0 / Double(trialsB))).squareRoot()
        guard standardError > 0 else {
            return TestResult(name: name, statistic: 0, degreesOfFreedom: nil, pValue: 1,
                              interpretation: "Nessuna differenza misurabile fra le due serie.")
        }
        let z = (pA - pB) / standardError
        let p = 2 * (1 - standardNormalCDF(abs(z)))
        let interpretation: String
        if p >= 0.05 {
            interpretation = "La differenza rispetto alla baseline casuale non è statisticamente significativa (p = \(format(p))). \(Disclaimer.noEdge)"
        } else if z > 0 {
            interpretation = "La strategia mostra una differenza positiva statisticamente significativa nel periodo testato (p = \(format(p))). Il risultato riguarda il campione analizzato e non implica capacità predittiva."
        } else {
            interpretation = "La strategia ha fatto peggio della baseline casuale in modo statisticamente significativo (p = \(format(p)))."
        }
        return TestResult(name: name, statistic: z, degreesOfFreedom: nil, pValue: p, interpretation: interpretation)
    }

    // MARK: - Funzioni speciali

    /// Funzione di ripartizione della normale standard.
    static func standardNormalCDF(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.0.squareRoot())
    }

    /// Funzione gamma incompleta regolarizzata P(a, x), con serie e frazione continua.
    static func regularizedLowerGamma(a: Double, x: Double) -> Double {
        guard x >= 0, a > 0 else { return 0 }
        if x == 0 { return 0 }
        if x < a + 1 {
            // Sviluppo in serie.
            var sum = 1.0 / a
            var term = sum
            var n = 1.0
            while n < 500 {
                term *= x / (a + n)
                sum += term
                if abs(term) < abs(sum) * 1e-15 { break }
                n += 1
            }
            return sum * exp(-x + a * log(x) - lgamma(a))
        } else {
            // Frazione continua (algoritmo di Lentz) per Q(a, x).
            let tiny = 1e-300
            var b = x + 1 - a
            var c = 1 / tiny
            var d = 1 / b
            var h = d
            var i = 1.0
            while i < 500 {
                let an = -i * (i - a)
                b += 2
                d = an * d + b
                if abs(d) < tiny { d = tiny }
                c = b + an / c
                if abs(c) < tiny { c = tiny }
                d = 1 / d
                let delta = d * c
                h *= delta
                if abs(delta - 1) < 1e-15 { break }
                i += 1
            }
            let q = exp(-x + a * log(x) - lgamma(a)) * h
            return 1 - q
        }
    }

    private static func format(_ value: Double) -> String {
        if value < 0.0001 { return "< 0,0001" }
        return String(format: "%.4f", value).replacingOccurrences(of: ".", with: ",")
    }
}
