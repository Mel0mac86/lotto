import SwiftUI
import Charts

/// **🤖 AI ANALYST** — modulo sperimentale di machine learning.
struct MLView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: MLViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                AppCard(title: "Modulo sperimentale", icon: "cpu") {
                    Text(Disclaimer.machineLearning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let viewModel {
                    @Bindable var bindable = viewModel
                    AppCard(title: "Configurazione", icon: "slider.horizontal.3") {
                        FilterBar(filter: $bindable.filter)
                        Picker("Modello", selection: $bindable.selectedModel) {
                            ForEach(MLModelKind.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(viewModel.selectedModel.purpose)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Task { await viewModel.run() }
                        } label: {
                            Label("Esegui", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunning)
                    }

                    if viewModel.isRunning {
                        ProgressOverlay(title: "Addestramento e valutazione…").frame(maxWidth: .infinity)
                    }

                    if let message = viewModel.message {
                        AppCard {
                            Label(message, systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    switch viewModel.selectedModel {
                    case .logisticRegression, .randomForest, .gradientBoosting:
                        if let evaluation = viewModel.evaluation { evaluationCard(evaluation) }
                    case .clustering:
                        if !viewModel.clusters.isEmpty { clustersCard(viewModel.clusters) }
                    case .anomalyDetection:
                        if !viewModel.anomalies.isEmpty { anomaliesCard(viewModel.anomalies) }
                    case .bayesian:
                        if !viewModel.posteriors.isEmpty {
                            bayesianCard(viewModel.posteriors, summary: viewModel.bayesianSummary)
                        }
                    }
                }

                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("AI Analyst")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel == nil { viewModel = MLViewModel(app: app) } }
    }

    // MARK: - Card

    private func evaluationCard(_ evaluation: MLEvaluation) -> some View {
        AppCard(title: evaluation.modelName, icon: "brain") {
            HStack {
                MetricTile(title: "Campioni train", value: "\(evaluation.trainingSamples)")
                MetricTile(title: "Campioni test", value: "\(evaluation.testSamples)")
            }
            HStack {
                MetricTile(title: "AUC", value: Theme.decimal(evaluation.auc, digits: 3),
                           caption: "0,500 = casuale",
                           tint: evaluation.auc > 0.55 ? Theme.medium : Theme.high)
                MetricTile(title: "Accuratezza", value: Theme.percent(evaluation.accuracy * 100, digits: 2))
                MetricTile(title: "Baseline", value: Theme.percent(evaluation.baselineAccuracy * 100, digits: 2))
            }
            HStack {
                MetricTile(title: "Log loss", value: Theme.decimal(evaluation.logLoss, digits: 4))
                MetricTile(title: "Log loss baseline", value: Theme.decimal(evaluation.baselineLogLoss, digits: 4))
            }
            if let coreMLSummary = evaluation.coreMLSummary {
                Text(coreMLSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 4)
            Text(evaluation.verdict)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(evaluation.significance.interpretation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Lo split fra addestramento e test è temporale: il modello viene valutato solo su estrazioni successive a quelle su cui è stato addestrato.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func clustersCard(_ clusters: [NumberCluster]) -> some View {
        AppCard(title: "Clustering dei numeri", icon: "circle.hexagongrid") {
            ForEach(clusters) { cluster in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(cluster.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(cluster.numbers.count) numeri")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(cluster.profile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cluster.numbers.map { Theme.number($0) }.joined(separator: "  "))
                        .font(.caption2.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 5)
                Divider()
            }
            Text("Il clustering descrive somiglianze fra profili storici. Gruppi simili emergono anche da dati puramente casuali.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func anomaliesCard(_ anomalies: [AnomalyScore]) -> some View {
        AppCard(title: "Numeri con profilo più atipico", icon: "exclamationmark.triangle") {
            ForEach(anomalies) { anomaly in
                HStack(alignment: .top, spacing: 12) {
                    NumberBall(number: anomaly.number, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Distanza dal profilo medio: \(Theme.decimal(anomaly.distance, digits: 2))")
                            .font(.caption.weight(.medium))
                        Text(anomaly.explanation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private func bayesianCard(_ posteriors: [BayesianModel.Posterior], summary: String?) -> some View {
        AppCard(title: "Probabilità a posteriori", icon: "function") {
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 4)
            }
            Chart(posteriors) { posterior in
                BarMark(x: .value("Numero", posterior.number),
                        y: .value("Scostamento %", posterior.deviationPercent))
                .foregroundStyle(posterior.containsTheoretical ? Theme.high.opacity(0.7) : Theme.low)
            }
            .chartXScale(domain: 1...90)
            .frame(height: 180)
            Text("Scostamento percentuale della media a posteriori rispetto alla probabilità teorica. In rosso i numeri il cui intervallo di credibilità al 95% non contiene il valore teorico.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Indice del "Laboratorio": backtest, Monte Carlo, ML, pattern, confronto.
struct LabHomeView: View {
    var body: some View {
        List {
            Section("Verifica delle strategie") {
                NavigationLink { BacktestView() } label: {
                    Label("Backtest e validazione", systemImage: "flask")
                }
                NavigationLink { MonteCarloView() } label: {
                    Label("Simulazione Monte Carlo", systemImage: "dice")
                }
            }
            Section("Modelli e pattern") {
                NavigationLink { MLView() } label: {
                    Label("AI Analyst", systemImage: "brain")
                }
                NavigationLink { PatternView() } label: {
                    Label("Trova pattern", systemImage: "magnifyingglass")
                }
            }
            Section("Combinazioni") {
                NavigationLink { CompareView() } label: {
                    Label("Confronto combinazioni", systemImage: "arrow.left.arrow.right")
                }
            }
            Section {
                DisclaimerBanner()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Laboratorio")
    }
}
