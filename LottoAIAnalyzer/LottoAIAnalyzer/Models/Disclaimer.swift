import Foundation

/// Testi ricorrenti sul significato (e sui limiti) delle analisi.
///
/// Sono centralizzati qui perché l'app deve essere coerente ovunque:
/// nessuna schermata può presentare un'analisi come previsione.
enum Disclaimer {
    static let primary = """
    Le estrazioni sono casuali. Le analisi statistiche degli estratti passati non modificano la \
    probabilità matematica di vincita. Le combinazioni generate sono suggerimenti statistici e \
    non previsioni certe.
    """

    static let score = """
    Score statistico basato sui dati storici selezionati. Non rappresenta la probabilità reale \
    che la combinazione venga estratta.
    """

    static let explainer = """
    Questi dati descrivono il passato e non aumentano la probabilità matematica dell'estrazione futura.
    """

    static let delay = """
    Il ritardo descrive quante estrazioni sono trascorse dall'ultima uscita. Un numero ritardatario \
    non ha una probabilità matematica maggiore di uscire: ogni estrazione è indipendente dalle precedenti.
    """

    static let machineLearning = """
    Il modulo di machine learning è sperimentale e serve a descrivere e classificare i pattern storici. \
    Non è, e non può essere, uno strumento di previsione di un evento casuale.
    """

    static let noEdge = "Nessun vantaggio predittivo dimostrato."

    static let backtest = """
    Il backtest è walk-forward: a ogni passo l'algoritmo vede soltanto le estrazioni precedenti alla data \
    simulata. I risultati descrivono il comportamento storico della strategia e non garantiscono risultati futuri.
    """

    static let monteCarlo = """
    La simulazione Monte Carlo genera estrazioni puramente casuali. Serve a verificare se i pattern \
    osservati nei dati storici sono compatibili con il caso.
    """
}
