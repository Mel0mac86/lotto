import SwiftUI
import Charts

/// **MONTE CARLO** — confronto fra estrazioni simulate e dati storici.
struct MonteCarloView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: MonteCarloViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    @Bindable var bindable = viewModel
                    AppCard(title: "Configurazione", icon: "slider.horizontal.3") {
                        FilterBar(filter: $bindable.filter)
                        Picker("Estrazioni simulate", selection: $bindable.iterations) {
                            ForEach(MonteCarloEngine.Iterations.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        Button {
                            Task { await viewModel.run() }
                        } label: {
                            Label("Avvia simulazione", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunning)
                    }

                    if viewModel.isRunning {
                        ProgressOverlay(title: "Simulazione in corso…").frame(maxWidth: .infinity)
                    }

                    if let result = viewModel.result {
                        conclusionCard(result)
                        testsCard(result)
                        frequencyChart(viewModel)
                        comparisonChart("Distribuzione delle somme", viewModel.sumComparison)
                        comparisonChart("Distribuzione pari/dispari", viewModel.parityComparison)
                        comparisonChart("Distribuzione per decine", viewModel.decadeComparison)
                        delaysCard(result)
                    }
                }
                DisclaimerBanner(text: Disclaimer.monteCarlo, icon: "dice")
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Monte Carlo")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel == nil { viewModel = MonteCarloViewModel(app: app) } }
    }

    private func conclusionCard(_ result: MonteCarloResult) -> some View {
        AppCard(title: "Conclusione", icon: "checkmark.seal") {
            Text(result.conclusion)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Simulazione di \(result.iterations) estrazioni completata in \(Theme.decimal(result.elapsed, digits: 2)) secondi.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func testsCard(_ result: MonteCarloResult) -> some View {
        AppCard(title: "Test statistici sui dati storici", icon: "function") {
            ForEach(result.tests) { test in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(test.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(test.isSignificant ? "scostamento" : "compatibile")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(test.isSignificant ? Theme.low : Theme.high)
                    }
                    Text(test.interpretation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private func frequencyChart(_ viewModel: MonteCarloViewModel) -> some View {
        AppCard(title: "Frequenza per numero", subtitle: "Storico contro simulazione casuale", icon: "chart.bar") {
            let points = viewModel.frequencyComparison
            let simulatedAverage = points.isEmpty ? 0
                : points.map(\.simulated).reduce(0, +) / Double(points.count)
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Numero", point.key), y: .value("Storico %", point.historical))
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                }
                RuleMark(y: .value("Simulato %", simulatedAverage))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartXScale(domain: 1...90)
            .frame(height: 200)
            Text("La linea orizzontale è la frequenza prodotta dalla simulazione puramente casuale.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func comparisonChart(_ title: String, _ points: [ComparisonPoint]) -> some View {
        AppCard(title: title, icon: "chart.bar.xaxis") {
            Chart(points) { point in
                BarMark(x: .value("Categoria", point.label), y: .value("%", point.simulated))
                    .position(by: .value("Serie", "Simulato"))
                    .foregroundStyle(Theme.neutral.opacity(0.45))
                BarMark(x: .value("Categoria", point.label), y: .value("%", point.historical))
                    .position(by: .value("Serie", "Storico"))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 170)
        }
    }

    private func delaysCard(_ result: MonteCarloResult) -> some View {
        AppCard(title: "Ritardi massimi", subtitle: "Storico contro simulazione", icon: "hourglass") {
            let simulatedMax = result.simulatedMaxDelays.max() ?? 0
            let historicalMax = result.historicalMaxDelays.max() ?? 0
            let simulatedMean = result.simulatedMaxDelays.isEmpty ? 0
                : Double(result.simulatedMaxDelays.reduce(0, +)) / Double(result.simulatedMaxDelays.count)
            let historicalMean = result.historicalMaxDelays.isEmpty ? 0
                : Double(result.historicalMaxDelays.reduce(0, +)) / Double(result.historicalMaxDelays.count)

            HStack {
                MetricTile(title: "Rit. max storico", value: "\(historicalMax)")
                MetricTile(title: "Rit. max simulato", value: "\(simulatedMax)")
            }
            HStack {
                MetricTile(title: "Media storica", value: Theme.decimal(historicalMean))
                MetricTile(title: "Media simulata", value: Theme.decimal(simulatedMean))
            }
            Text("I ritardi simulati sono calcolati su un numero di estrazioni molto maggiore di quello storico: i massimi non sono direttamente confrontabili, mentre l'ordine di grandezza delle medie sì.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
