import SwiftUI

/// **CINQUINA AI** (sestina per il SuperEnalotto) con le quattro modalità.
struct QuintupleView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: GeneratorViewModel?
    @State private var context: AnalysisContext?
    let game: GameType

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    controls(viewModel)

                    if viewModel.isWorking {
                        ProgressOverlay(title: viewModel.progressLabel ?? "Generazione…")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.quintuples.isEmpty {
                        EmptyStateView(icon: "target",
                                       title: game == .lotto ? "Nessuna cinquina generata" : "Nessuna sestina generata",
                                       message: "Scegli una modalità e genera le combinazioni.",
                                       actionTitle: "Genera") {
                            Task { await generate() }
                        }
                    } else {
                        ForEach(viewModel.quintuples.ranked()) { item in
                            resultCard(rank: item.rank, result: item.element, viewModel: viewModel)
                        }
                    }
                }
                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle(game == .lotto ? "Cinquina AI" : "Sestina AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExportMenu {
                    guard let viewModel, let context, !viewModel.quintuples.isEmpty else { return nil }
                    return ReportBuilder.combinationsReport(results: viewModel.quintuples, context: context)
                }
            }
        }
        .task {
            if viewModel == nil {
                let model = GeneratorViewModel(app: app)
                model.game = game
                viewModel = model
            }
        }
    }

    private func controls(_ viewModel: GeneratorViewModel) -> some View {
        AppCard(title: "Modalità di generazione", icon: "slider.horizontal.3") {
            ForEach(QuintupleMode.allCases) { mode in
                Button {
                    viewModel.quintupleMode = mode
                    viewModel.strategy = mode.strategy
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: viewModel.quintupleMode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(viewModel.quintupleMode == mode ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName).font(.subheadline.weight(.medium))
                            Text(mode.subtitle).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }

            Divider().padding(.vertical, 4)

            if game.usesWheels {
                Picker("Ruota", selection: Binding(get: { viewModel.wheel }, set: { viewModel.wheel = $0 })) {
                    ForEach(Wheel.allCases) { wheel in Text(wheel.displayName).tag(wheel) }
                }
                .pickerStyle(.menu)
            }
            Picker("Periodo", selection: Binding(get: { viewModel.period }, set: { viewModel.period = $0 })) {
                ForEach(AnalysisPeriod.allCases) { period in Text(period.displayName).tag(period) }
            }
            .pickerStyle(.menu)

            Stepper("Combinazioni: \(viewModel.combinationCount)",
                    value: Binding(get: { viewModel.combinationCount }, set: { viewModel.combinationCount = $0 }),
                    in: 1...10)
                .font(.subheadline)

            Button {
                Task { await generate() }
            } label: {
                Label("Genera", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isWorking)
        }
    }

    private func resultCard(rank: Int, result: GeneratedResult, viewModel: GeneratorViewModel) -> some View {
        AppCard {
            HStack {
                Text("Combinazione \(rank)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ScoreBadge(score: result.combination.score)
            }
            CombinationRow(numbers: result.combination.numbers, scores: scoreMap(result.combination.numbers), size: 46)

            HStack {
                MetricTile(title: "Pari/disp.", value: "\(result.combination.evenCount)/\(result.combination.oddCount)")
                MetricTile(title: "1–45 / 46–90", value: "\(result.combination.lowCount)/\(result.combination.highCount)")
                MetricTile(title: "Somma", value: "\(result.combination.sum)")
            }

            HStack {
                NavigationLink {
                    ResultDetailView(result: result, context: context) {
                        viewModel.save(result)
                    }
                } label: {
                    Label("Dettaglio e spiegazione", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                }
                Spacer()
                Button {
                    viewModel.toggleSelection(result)
                } label: {
                    Image(systemName: result.isSelected ? "checkmark.square.fill" : "square")
                }
                Button {
                    viewModel.save(result)
                } label: {
                    Image(systemName: "bookmark")
                }
            }
            .padding(.top, 4)
        }
    }

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
    }
}
