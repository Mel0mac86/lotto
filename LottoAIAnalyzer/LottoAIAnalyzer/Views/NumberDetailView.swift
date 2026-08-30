import SwiftUI
import Charts

/// Scheda di dettaglio di un singolo numero.
struct NumberDetailView: View {
    @Environment(AppModel.self) private var app
    let number: Int
    let filter: AnalysisFilter

    @State private var viewModel: AnalysisViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let context = viewModel?.context, !context.isEmpty {
                    header(context)
                    metrics(context)
                    yearlyChart
                    monthlyChart
                    partners(context)
                    AppCard(title: "Lettura in linguaggio naturale", icon: "text.bubble") {
                        Text(AIExplainer.explainNumber(number, context: context))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ProgressOverlay(title: "Calcolo…")
                }
                DisclaimerBanner(text: Disclaimer.delay, icon: "hourglass")
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Numero \(Theme.number(number))")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let model = AnalysisViewModel(app: app, filter: filter)
            viewModel = model
            await model.load()
        }
    }

    private func header(_ context: AnalysisContext) -> some View {
        AppCard {
            HStack(spacing: 16) {
                NumberBall(number: number, score: context.score(of: number), size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    ScoreBadge(score: context.score(of: number))
                    Text(context.filter.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(HotColdEngine.tags(for: context.stats(of: number)), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private func metrics(_ context: AnalysisContext) -> some View {
        let stats = context.stats(of: number)
        let scoreEntry = context.scores[number]
        return AppCard(title: "Indicatori", icon: "chart.bar.doc.horizontal") {
            HStack {
                MetricTile(title: "Uscite", value: "\(stats.occurrences)", caption: "su \(context.drawCount)")
                MetricTile(title: "Frequenza", value: Theme.percent(stats.frequency * 100, digits: 2),
                           caption: "attesa \(Theme.percent(stats.expectedFrequency * 100, digits: 2))")
                MetricTile(title: "Percentile", value: Theme.decimal(stats.frequencyPercentile, digits: 0))
            }
            HStack {
                MetricTile(title: "Ritardo", value: "\(stats.currentDelay)")
                MetricTile(title: "Ritardo medio", value: Theme.decimal(stats.averageDelay))
                MetricTile(title: "Ritardo max", value: "\(stats.maxDelay)")
            }
            ScoreBar(label: "Ritardo attuale / massimo storico", value: min(stats.delayRatio * 100, 100))

            if let components = scoreEntry?.components {
                Divider().padding(.vertical, 4)
                ForEach(components.labelledValues.filter { $0.label != "Equilibrio" }) { item in
                    ScoreBar(label: item.label, value: item.value)
                }
            }
        }
    }

    private var yearlyChart: some View {
        AppCard(title: "Uscite per anno", icon: "calendar") {
            Chart(viewModel?.yearlySeries(for: number) ?? []) { point in
                BarMark(x: .value("Anno", String(point.year)), y: .value("Uscite", point.count))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
            .frame(height: 150)
        }
    }

    private var monthlyChart: some View {
        AppCard(title: "Uscite per mese", subtitle: "Aggregato su tutto il periodo selezionato", icon: "calendar.badge.clock") {
            Chart(viewModel?.monthlySeries(for: number) ?? []) { point in
                BarMark(x: .value("Mese", point.label), y: .value("Uscite", point.count))
                    .foregroundStyle(Theme.medium.opacity(0.85))
            }
            .frame(height: 150)
        }
    }

    private func partners(_ context: AnalysisContext) -> some View {
        let matrix = CoOccurrenceMatrix.build(from: context.draws, drawnPerDraw: context.game.drawnCount)
        let partners = matrix.topPartners(of: number, limit: 8)
        return AppCard(title: "Numeri più ricorrenti insieme", icon: "link") {
            ForEach(partners) { partner in
                HStack {
                    NumberBall(number: partner.number, score: context.score(of: partner.number), size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(partner.count) uscite congiunte")
                            .font(.subheadline)
                        Text(partner.lift >= 1
                             ? "\(Theme.decimal((partner.lift - 1) * 100, digits: 0))% sopra l'atteso"
                             : "\(Theme.decimal((1 - partner.lift) * 100, digits: 0))% sotto l'atteso")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Theme.decimal(partner.lift, digits: 2))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(partner.lift > 1.15 ? Theme.high : .secondary)
                }
                .padding(.vertical, 3)
            }
        }
    }
}
