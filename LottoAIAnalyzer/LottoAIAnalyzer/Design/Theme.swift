import SwiftUI
import UIKit

/// Palette e metriche condivise. Stile "fintech": superfici neutre, accenti sobri,
/// nessun elemento da casinò.
enum Theme {

    // MARK: - Colori

    static let accent = Color("AccentColor")

    static let high = Color(red: 0.13, green: 0.70, blue: 0.45)     // verde
    static let medium = Color(red: 0.95, green: 0.70, blue: 0.13)   // giallo
    static let low = Color(red: 0.86, green: 0.31, blue: 0.31)      // rosso
    static let neutral = Color.secondary

    static func color(for band: ScoreBand) -> Color {
        switch band {
        case .high: return high
        case .medium: return medium
        case .low: return low
        }
    }

    static func color(forScore score: Double) -> Color {
        color(for: ScoreBand(score: score))
    }

    /// Sfondo delle card, adattivo su tema chiaro e scuro.
    static var cardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    static var pageBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    static var separator: Color {
        Color(uiColor: .separator)
    }

    // MARK: - Metriche

    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let stackSpacing: CGFloat = 14

    // MARK: - Formattazione

    static let italianLocale = Locale(identifier: "it_IT")

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = italianLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = italianLocale
        formatter.dateFormat = "dd/MM/yy"
        return formatter
    }()

    static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = italianLocale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = italianLocale
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func percent(_ value: Double, digits: Int = 1) -> String {
        decimal(value, digits: digits) + "%"
    }

    static func currency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? decimal(value, digits: 2) + " €"
    }

    static func number(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
