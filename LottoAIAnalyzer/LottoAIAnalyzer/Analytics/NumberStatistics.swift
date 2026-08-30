import Foundation

/// Statistiche calcolate per un singolo numero all'interno di un insieme di estrazioni.
struct NumberStatistics: Hashable, Identifiable, Sendable {
    let number: Int

    /// Quante volte il numero è uscito nel periodo analizzato.
    var occurrences: Int = 0
    /// Frequenza relativa: uscite / estrazioni analizzate.
    var frequency: Double = 0
    /// Frequenza attesa in caso di pura casualità (numeri estratti / 90).
    var expectedFrequency: Double = 0
    /// Rapporto frequenza osservata / frequenza attesa. 1.0 = perfettamente in media.
    var frequencyRatio: Double = 0

    /// Estrazioni trascorse dall'ultima uscita (0 = uscito nell'ultima estrazione).
    var currentDelay: Int = 0
    /// Media dei ritardi storici osservati.
    var averageDelay: Double = 0
    /// Ritardo massimo mai osservato nel periodo.
    var maxDelay: Int = 0
    /// Ritardo attuale in percentuale rispetto al massimo storico.
    var delayRatio: Double = 0
    /// Data dell'ultima uscita.
    var lastSeen: Date?
    /// Indice (0-based) dell'ultima estrazione in cui è uscito.
    var lastSeenIndex: Int?

    /// Frequenza nell'ultimo 25% delle estrazioni del periodo.
    var recentFrequency: Double = 0
    /// recentFrequency / frequency. > 1 = in crescita.
    var trendRatio: Double = 1
    /// Coefficiente di variazione delle frequenze per sotto-periodo (0 = stabilissimo).
    var volatility: Double = 0

    /// Numero medio di co-occorrenze con gli altri numeri, normalizzato.
    var coOccurrenceStrength: Double = 0

    /// Percentile della frequenza rispetto agli altri 89 numeri (0–100).
    var frequencyPercentile: Double = 0

    /// Ruote su cui il numero mostra frequenza sopra la media (solo analisi multi-ruota).
    var activeWheels: [Wheel] = []

    var id: Int { number }

    var isHot: Bool { trendRatio >= 1.10 }
    var isCold: Bool { trendRatio <= 0.90 }
    var isOverdue: Bool { averageDelay > 0 && Double(currentDelay) > averageDelay * 1.5 }
}

/// Statistiche complessive di un insieme di estrazioni.
struct DatasetStatistics: Sendable {
    var drawCount: Int = 0
    var firstDate: Date?
    var lastDate: Date?
    var numbers: [Int: NumberStatistics] = [:]

    /// Distribuzione delle somme delle combinazioni estratte.
    var sums: [Int] = []
    /// Conteggio delle estrazioni per numero di pari (0…6).
    var evenDistribution: [Int: Int] = [:]
    /// Conteggio delle estrazioni per numero di numeri bassi 1–45 (0…6).
    var lowDistribution: [Int: Int] = [:]
    /// Uscite per decina (0 = 1–10, 1 = 11–20, …, 8 = 81–90).
    var decadeDistribution: [Int: Int] = [:]
    /// Uscite per cifra delle unità (0…9).
    var unitDistribution: [Int: Int] = [:]
    /// Estrazioni contenenti almeno una coppia consecutiva.
    var drawsWithConsecutives: Int = 0
    /// Uscite per anno: [anno: [numero: uscite]].
    var byYear: [Int: [Int: Int]] = [:]
    /// Uscite per mese (1…12).
    var byMonth: [Int: [Int: Int]] = [:]
    /// Uscite per ruota (solo Lotto).
    var byWheel: [Wheel: [Int: Int]] = [:]

    var sortedByFrequency: [NumberStatistics] {
        numbers.values.sorted { $0.occurrences > $1.occurrences }
    }

    var sortedByDelay: [NumberStatistics] {
        numbers.values.sorted { $0.currentDelay > $1.currentDelay }
    }

    var averageSum: Double {
        guard !sums.isEmpty else { return 0 }
        return Double(sums.reduce(0, +)) / Double(sums.count)
    }

    var isEmpty: Bool { drawCount == 0 }
}
