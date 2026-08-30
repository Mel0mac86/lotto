import Foundation

/// Giochi supportati dall'applicazione.
enum GameType: String, Codable, CaseIterable, Identifiable, Sendable {
    case lotto
    case superenalotto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lotto: return "Lotto"
        case .superenalotto: return "SuperEnalotto"
        }
    }

    var symbol: String {
        switch self {
        case .lotto: return "🎱"
        case .superenalotto: return "⭐️"
        }
    }

    /// Intervallo dei numeri giocabili (identico per i due giochi: 1...90).
    var numberRange: ClosedRange<Int> { 1...90 }

    /// Numeri estratti per ogni estrazione.
    var drawnCount: Int {
        switch self {
        case .lotto: return 5
        case .superenalotto: return 6
        }
    }

    /// Il gioco prevede le ruote?
    var usesWheels: Bool { self == .lotto }

    /// Il gioco prevede il numero Jolly?
    var usesJolly: Bool { self == .superenalotto }

    /// Il gioco prevede il numero SuperStar?
    var usesSuperStar: Bool { self == .superenalotto }
}
