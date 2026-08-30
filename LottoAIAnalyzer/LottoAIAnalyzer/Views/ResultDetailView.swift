import SwiftUI
import Charts

/// **PAGINA RISULTATO** — dettaglio di una combinazione generata.
struct ResultDetailView: View {
    @Environment(AppModel.self) private var app
    let result: GeneratedResult
    var context: AnalysisContext? = nil
    var onSave: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                combinationCard
                analysisCard
                distributionCard
                componentsCard
                explanationCards
                DisclaimerBanner(text: Disclaimer.score, icon: "info.circle")
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Combinazione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onSave?()
                } label: {
                    Image(systemName: "bookmark")
                }
            }
        }
    }

    private var combinationCard: some View {
        AppCard {
            Text("🎯 COMBINAZIONE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            CombinationRow(numbers: result.combination.numbers,
                           scores: scoreMap,
                           size: 52)
            .padding(.vertical, 4)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Statistical Score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(result.combination.score.rounded()))/100")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.color(for: result.combination.band))
            }
            Text("\(result.combination.band.emoji) \(result.combination.band.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(result.filter.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var analysisCard: some View {
        let components = result.combination.components
        return AppCard(title: "Analisi", icon: "chart.bar.doc.horizontal") {
            row("🔥 Frequenza", components.frequency)
            row("⏳ Ritardo", components.delay)
            row("📈 Trend", components.trend)
            row("🔗 Co-occorrenza", components.coOccurrence)
            row("⚖️ Equilibrio", components.balance)
        }
    }

    private func row(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(qualitativeLabel(value))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.color(forScore: value))
            Text("(\(Int(value.rounded())))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func qualitativeLabel(_ value: Double) -> String {
        switch value {
        case 70...: return "alta"
        case 40..<70: return "media"
        default: return "bassa"
        }
    }

    private var distributionCard: some View {
        let combination = result.combination
        return AppCard(title: "Distribuzione", icon: "square.grid.3x3") {
            HStack {
                MetricTile(title: "Pari", value: "\(combination.evenCount)")
                MetricTile(title: "Dispari", value: "\(combination.oddCount)")
                MetricTile(title: "1–45", value: "\(combination.lowCount)")
                MetricTile(title: "46–90", value: "\(combination.highCount)")
                MetricTile(title: "Somma", value: "\(combination.sum)")
            }
            Divider().padding(.vertical, 4)
            Chart {
                ForEach(0...8, id: \.self) { decade in
                    BarMark(x: .value("Decina", "\(decade * 10 + 1)–\(decade * 10 + 10)"),
                            y: .value("Numeri", combination.decadeDistribution[decade] ?? 0))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                }
            }
            .frame(height: 120)
            Text("Distanza media fra numeri consecutivi della combinazione: \(Theme.decimal(combination.averageGap)).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var componentsCard: some View {
        AppCard(title: "Scomposizione dell'indice", icon: "slider.horizontal.3") {
            ForEach(result.combination.components.labelledValues) { item in
                ScoreBar(label: item.label, value: item.value)
            }
        }
    }

    private var explanationCards: some View {
        ForEach(result.explanation) { section in
            AppCard(title: section.title, icon: section.icon) {
                Text(section.body)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scoreMap: [Int: Double] {
        guard let context else { return [:] }
        var map: [Int: Double] = [:]
        for number in result.combination.numbers { map[number] = context.score(of: number) }
        return map
    }
}
