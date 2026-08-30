import SwiftUI

/// **🔮 GENERA COMBINAZIONE** — procedura guidata: gioco → strategia → periodo → risultati.
struct SmartGeneratorView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: GeneratorViewModel?
    @State private var context: AnalysisContext?
    @State private var step: Step = .setup

    enum Step { case setup, results }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    switch step {
                    case .setup:
                        gameCard(viewModel)
                        strategyCard(viewModel)
                        periodCard(viewModel)
                        generateButton(viewModel)
                    case .results:
                        resultsSection(viewModel)
                    }
                }
                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("🔮 Genera combinazione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if step == .results {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Modifica") { step = .setup }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ExportMenu {
                        guard let viewModel, let context, !viewModel.quintuples.isEmpty else { return nil }
                        return ReportBuilder.combinationsReport(results: viewModel.quintuples, context: context)
                    }
                }
            }
        }
        .task {
            if viewModel == nil { viewModel = GeneratorViewModel(app: app) }
        }
    }

    // MARK: - Passi

    private func gameCard(_ viewModel: GeneratorViewModel) -> some View {
        AppCard(title: "1. Gioco", icon: "gamecontroller") {
            Picker("Gioco", selection: Binding(get: { viewModel.game }, set: { viewModel.game = $0 })) {
                ForEach(GameType.allCases) { game in
                    Text("\(game.symbol) \(game.displayName)").tag(game)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.game.usesWheels {
                Toggle("Analizza tutte le ruote",
                       isOn: Binding(get: { viewModel.useAllWheels }, set: { viewModel.useAllWheels = $0 }))
                    .font(.subheadline)
                if !viewModel.useAllWheels {
                    Picker("Ruota", selection: Binding(get: { viewModel.wheel }, set: { viewModel.wheel = $0 })) {
                        ForEach(Wheel.allCases) { wheel in Text(wheel.displayName).tag(wheel) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func strategyCard(_ viewModel: GeneratorViewModel) -> some View {
        AppCard(title: "2. Strategia", icon: "target") {
            ForEach(GenerationStrategy.allCases.filter { $0 != .conservative && $0 != .diversified }) { strategy in
                Button {
                    viewModel.strategy = strategy
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: viewModel.strategy == strategy ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(viewModel.strategy == strategy ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(strategy.displayName).font(.subheadline.weight(.medium))
                            Text(strategy.explanation).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
    }

    private func periodCard(_ viewModel: GeneratorViewModel) -> some View {
        AppCard(title: "3. Periodo", icon: "calendar") {
            Picker("Periodo", selection: Binding(get: { viewModel.period }, set: { viewModel.period = $0 })) {
                ForEach([AnalysisPeriod.oneYear, .threeYears, .fiveYears, .tenYears, .all]) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Stepper("Combinazioni da generare: \(viewModel.combinationCount)",
                    value: Binding(get: { viewModel.combinationCount }, set: { viewModel.combinationCount = $0 }),
                    in: 1...10)
                .font(.subheadline)
        }
    }

    private func generateButton(_ viewModel: GeneratorViewModel) -> some View {
        VStack(spacing: 8) {
            Button {
                Task { await generate() }
            } label: {
                if viewModel.isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("🔮 Genera combinazione", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isWorking || app.drawCount(for: viewModel.game) == 0)

            if app.drawCount(for: viewModel.game) == 0 {
                Text("Importa prima lo storico di \(viewModel.game.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resultsSection(_ viewModel: GeneratorViewModel) -> some View {
        VStack(spacing: Theme.stackSpacing) {
            AppCard(title: "Impostazioni usate", icon: "info.circle") {
                LabeledValueRow(label: "Gioco", value: viewModel.game.displayName)
                if viewModel.game.usesWheels {
                    LabeledValueRow(label: "Ruota", value: viewModel.useAllWheels ? "Tutte le ruote" : viewModel.wheel.displayName)
                }
                LabeledValueRow(label: "Strategia", value: viewModel.strategy.displayName)
                LabeledValueRow(label: "Periodo", value: viewModel.period.displayName)
                LabeledValueRow(label: "Estrazioni analizzate", value: "\(context?.drawCount ?? 0)")
            }

            ForEach(viewModel.quintuples.ranked()) { entry in
                let result = entry.element
                AppCard {
                    HStack {
                        Text("Combinazione \(entry.rank)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        ScoreBadge(score: result.combination.score)
                    }
                    CombinationRow(numbers: result.combination.numbers,
                                   scores: scoreMap(result.combination.numbers), size: 46)

                    if let firstReason = result.combination.reasons.first {
                        Text(firstReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        MetricTile(title: "Pari/disp.", value: "\(result.combination.evenCount)/\(result.combination.oddCount)")
                        MetricTile(title: "1–45/46–90", value: "\(result.combination.lowCount)/\(result.combination.highCount)")
                        MetricTile(title: "Somma", value: "\(result.combination.sum)")
                    }

                    HStack {
                        NavigationLink {
                            ResultDetailView(result: result, context: context) { viewModel.save(result) }
                        } label: {
                            Label("Motivazioni e statistiche", systemImage: "doc.text.magnifyingglass")
                                .font(.subheadline)
                        }
                        Spacer()
                        Button { viewModel.toggleSelection(result) } label: {
                            Image(systemName: result.isSelected ? "checkmark.square.fill" : "square")
                        }
                        Button { viewModel.save(result) } label: {
                            Image(systemName: "bookmark")
                        }
                    }
                    .padding(.top, 4)
                }
            }

            if !viewModel.selectedResults.isEmpty {
                NavigationLink {
                    CompareView(preselected: viewModel.selectedResults)
                } label: {
                    Label("Confronta le \(viewModel.selectedResults.count) combinazioni selezionate",
                          systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Logica

    private func scoreMap(_ numbers: [Int]) -> [Int: Double] {
        guard let context else { return [:] }
        var map: [Int: Double] = [:]
        for number in numbers { map[number] = context.score(of: number) }
        return map
    }

    private func generate() async {
        guard let viewModel else { return }
        await viewModel.generateQuintuples()
        let filter = viewModel.filter
        let weights = viewModel.strategy.weights
        let draws = app.draws(for: filter.game)
        context = await app.compute { AnalysisContext(filter: filter, allDraws: draws, weights: weights) }
        if !viewModel.quintuples.isEmpty { step = .results }
    }
}
