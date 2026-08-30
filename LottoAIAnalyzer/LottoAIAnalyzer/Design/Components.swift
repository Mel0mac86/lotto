import SwiftUI

/// Card standard dell'app.
struct AppCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || icon != nil {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    if let title {
                        Text(title)
                            .font(.headline)
                    }
                    Spacer(minLength: 0)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Pallino con il numero estratto.
struct NumberBall: View {
    let number: Int
    var score: Double? = nil
    var size: CGFloat = 44

    private var tint: Color {
        guard let score else { return Color.accentColor }
        return Theme.color(forScore: score)
    }

    var body: some View {
        Text(Theme.number(number))
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 1))
            .accessibilityLabel("Numero \(number)")
    }
}

/// Riga di numeri di una combinazione.
struct CombinationRow: View {
    let numbers: [Int]
    var scores: [Int: Double] = [:]
    var size: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            ForEach(numbers, id: \.self) { number in
                NumberBall(number: number, score: scores[number], size: size)
            }
        }
    }
}

/// Badge dell'indice statistico.
struct ScoreBadge: View {
    let score: Double
    var compact: Bool = false

    var body: some View {
        let band = ScoreBand(score: score)
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.color(for: band))
                .frame(width: 8, height: 8)
            Text("\(Int(score.rounded()))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if !compact {
                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.color(for: band).opacity(0.12), in: Capsule())
        .accessibilityLabel("Indice statistico \(Int(score.rounded())) su 100, \(band.label)")
    }
}

/// Barra orizzontale che rappresenta un valore 0–100.
struct ScoreBar: View {
    let label: String
    let value: Double
    var showsValue: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if showsValue {
                    Text("\(Int(value.rounded()))")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Theme.color(forScore: value))
                        .frame(width: max(proxy.size.width * value / 100, 3))
                }
            }
            .frame(height: 6)
        }
    }
}

/// Riquadro con l'avvertenza obbligatoria.
struct DisclaimerBanner: View {
    var text: String = Disclaimer.primary
    var icon: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Metrica compatta (etichetta + valore).
struct MetricTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stato vuoto con azione suggerita.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

/// Indicatore di elaborazione con percentuale.
struct ProgressOverlay: View {
    let title: String
    var progress: Double? = nil

    var body: some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 180)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Elemento numerato: permette di mostrare la posizione in classifica dentro una
/// `ForEach` senza ricorrere a `enumerated()`, i cui elementi sono tuple e non
/// possono essere indirizzati con un key path.
struct RankedItem<Element>: Identifiable {
    let rank: Int
    let element: Element
    var id: Int { rank }
}

extension Array {
    /// Numera gli elementi a partire da 1.
    func ranked() -> [RankedItem<Element>] {
        enumerated().map { RankedItem(rank: $0.offset + 1, element: $0.element) }
    }
}
