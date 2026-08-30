import SwiftUI
import Charts

/// **ANALISI CALDA/FREDDA** — hot, cold, overdue e combinazioni.
struct HotColdView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: AnalysisViewModel?
    @State private var temperature: TemperatureFilter
    let game: GameType

    init(game: GameType, initialFilter: TemperatureFilter = .hot) {
        self.game = game
        _temperature = State(initialValue: initialFilter)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    @Bindable var bindable = viewModel
                    FilterBar(filter: $bindable.filter, showsGamePicker: false) {
                        Task { await viewModel.load() }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TemperatureFilter.allCases) { item in
                            Button {
                                temperature = item
                            } label: {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(temperature == item ? Color.accentColor.opacity(0.18) : Theme.cardBackground,
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                AppCard(title: temperature.displayName, subtitle: temperature.description, icon: "thermometer.medium") {
                    let entries = viewModel?.temperatureEntries(temperature, limit: 30) ?? []
                    if entries.isEmpty {
                        Text("Nessun numero rientra in questo criterio nel periodo selezionato.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            NavigationLink {
                                if let filter = viewModel?.filter {
                                    NumberDetailView(number: entry.number, filter: filter)
                                }
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }

                if let context = viewModel?.context, !context.isEmpty {
                    trendChart(context)
                }

                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Hot / Cold")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                var filter = app.settings.defaultFilter()
                filter.game = game
                if !game.usesWheels { filter.wheelScope = .all }
                let model = AnalysisViewModel(app: app, filter: filter)
                viewModel = model
                await model.load()
            }
        }
    }

    private func row(_ entry: TemperatureEntry) -> some View {
        HStack(spacing: 12) {
            NumberBall(number: entry.number, score: entry.score, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.tags.joined(separator: "  "))
                    .font(.caption)
                Text("\(entry.statistics.occurrences) uscite · ritardo \(entry.statistics.currentDelay) · trend \(Theme.decimal(entry.statistics.trendRatio, digits: 2))×")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ScoreBadge(score: entry.score, compact: true)
        }
        .padding(.vertical, 5)
    }

    private func trendChart(_ context: AnalysisContext) -> some View {
        AppCard(title: "Trend: frequenza recente / frequenza del periodo", icon: "chart.line.uptrend.xyaxis") {
            let items = context.game.numberRange.compactMap { context.statistics.numbers[$0] }
            Chart(items) { item in
                BarMark(x: .value("Numero", item.number),
                        y: .value("Trend", item.trendRatio - 1))
                .foregroundStyle(item.trendRatio >= 1 ? Theme.high : Theme.low)
            }
            .chartXScale(domain: 1...90)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(Theme.decimal((doubleValue + 1) * 100, digits: 0) + "%")
                        }
                    }
                }
            }
            .frame(height: 180)
            Text("Valori sopra lo zero indicano una frequenza recente superiore a quella dell'intero periodo. Su estrazioni casuali queste oscillazioni sono normali.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
