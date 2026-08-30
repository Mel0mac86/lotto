import Foundation
import SwiftUI
import Observation

/// Preferenze dell'utente, salvate localmente in `UserDefaults`.
///
/// Nessun dato personale viene raccolto o inviato: le impostazioni restano sul
/// dispositivo e sono separate dall'archivio delle estrazioni.
///
/// - Note: i valori vivono in un'unica struttura `State` osservata; le proprietà
///   pubbliche sono calcolate e scrivono su disco a ogni modifica. Questo evita
///   gli osservatori `didSet`, che non sono compatibili con la macro `@Observable`.
@MainActor
@Observable
final class AppSettings {

    enum AppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
        case system, light, dark
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .system: return "Automatico"
            case .light: return "Chiaro"
            case .dark: return "Scuro"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    /// Contenuto serializzabile delle preferenze.
    struct State: Codable, Sendable {
        var weights: ScoringWeights = .balanced
        var remoteSources: [RemoteSource] = []
        var notificationsEnabled = true
        var autoUpdateEnabled = true
        var lastUpdateCheck: Date?
        var lastSuccessfulUpdate: Date?
        var appearance: AppearanceMode = .system
        var defaultGame: GameType = .lotto
        var defaultWheel: Wheel = .bari
        var defaultPeriod: AnalysisPeriod = .fiveYears
        var lottoPayouts: PayoutTable = .lotto
        var superenalottoPayouts: PayoutTable = .superenalotto
        var hasAcceptedDisclaimer = false
    }

    private static let storageKey = "app.settings.v1"

    @ObservationIgnored private let defaults: UserDefaults
    private var state: State

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            self.state = decoded
        } else {
            self.state = State()
        }
    }

    // MARK: - Proprietà

    var weights: ScoringWeights {
        get { state.weights }
        set { state.weights = newValue; persist() }
    }

    var remoteSources: [RemoteSource] {
        get { state.remoteSources }
        set { state.remoteSources = newValue; persist() }
    }

    var notificationsEnabled: Bool {
        get { state.notificationsEnabled }
        set { state.notificationsEnabled = newValue; persist() }
    }

    var autoUpdateEnabled: Bool {
        get { state.autoUpdateEnabled }
        set { state.autoUpdateEnabled = newValue; persist() }
    }

    var lastUpdateCheck: Date? {
        get { state.lastUpdateCheck }
        set { state.lastUpdateCheck = newValue; persist() }
    }

    var lastSuccessfulUpdate: Date? {
        get { state.lastSuccessfulUpdate }
        set { state.lastSuccessfulUpdate = newValue; persist() }
    }

    var appearance: AppearanceMode {
        get { state.appearance }
        set { state.appearance = newValue; persist() }
    }

    var defaultGame: GameType {
        get { state.defaultGame }
        set { state.defaultGame = newValue; persist() }
    }

    var defaultWheel: Wheel {
        get { state.defaultWheel }
        set { state.defaultWheel = newValue; persist() }
    }

    var defaultPeriod: AnalysisPeriod {
        get { state.defaultPeriod }
        set { state.defaultPeriod = newValue; persist() }
    }

    var lottoPayouts: PayoutTable {
        get { state.lottoPayouts }
        set { state.lottoPayouts = newValue; persist() }
    }

    var superenalottoPayouts: PayoutTable {
        get { state.superenalottoPayouts }
        set { state.superenalottoPayouts = newValue; persist() }
    }

    var hasAcceptedDisclaimer: Bool {
        get { state.hasAcceptedDisclaimer }
        set { state.hasAcceptedDisclaimer = newValue; persist() }
    }

    // MARK: - Derivati

    func payouts(for game: GameType) -> PayoutTable {
        game == .lotto ? lottoPayouts : superenalottoPayouts
    }

    func defaultFilter() -> AnalysisFilter {
        AnalysisFilter(game: defaultGame,
                       wheelScope: defaultGame.usesWheels ? .single(defaultWheel) : .all,
                       period: defaultPeriod)
    }

    /// Ripristina i valori di fabbrica (mantiene l'accettazione dell'avvertenza).
    func resetToDefaults() {
        var fresh = State()
        fresh.hasAcceptedDisclaimer = state.hasAcceptedDisclaimer
        state = fresh
        persist()
    }

    // MARK: - Persistenza

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
