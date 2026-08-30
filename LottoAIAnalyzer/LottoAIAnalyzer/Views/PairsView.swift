import SwiftUI

/// **GENERA AMBO** — top 10 ambi statisticamente interessanti.
struct PairsView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: GeneratorViewModel?
    @State private var context: AnalysisContext?
    @State private var expanded: Set<String> = []
    let game: GameType

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    controls(viewModel)

                    if viewModel.isWorking {
                        ProgressOverlay(title: viewModel.progressLabel ?? "Elaborazione…")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.pairs.isEmpty {
                        EmptyStateView(icon: "link",
                                       title: "Nessun ambo calcolato",
                                       message: "Tocca «Genera ambi» per analizzare tutte le 4.005 coppie possibili.",
                                       actionTitle: "Genera ambi") {
                            Task { await generate() }
                        }
                    } else {
                        header
                        ForEach(viewModel.pairs.ranked()) { item in
                            pairCard(rank: item.rank, pair: item.element)
                        }
                    }
                }
                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Ambi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExportMenu {
                    guard let viewModel, let context, !viewModel.pairs.isEmpty else { return nil }
                    return ReportBuilder.pairsReport(pairs: viewModel.pairs, context: context)
                }
            }
        }
        .task {
            if viewModel == nil {
                let model = GeneratorViewModel(app: app)
                model.game = game
                model.wheel = app.settings.defaultWheel
                viewModel = model
            }
        }
    }

    private func controls(_ viewModel: GeneratorViewModel) -> some View {
        AppCard {
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

            Button {
                Task { await generate() }
            } label: {
                Label("Genera ambi", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isWorking)
        }
    }

    private var header: some View {
        Text("TOP \(viewModel?.pairs.count ?? 0) AMBI STATISTICAMENTE INTERESSANTI")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pairCard(rank: Int, pair: PairResult) -> some View {
        AppCard {
            HStack(alignment: .center, spacing: 12) {
                Text("\(rank).")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                CombinationRow(numbers: pair.numbers,
                               scores: scoreMap(for: pair.numbers),
                               size: 42)
                Spacer()
                ScoreBadge(score: pair.score)
            }

            HStack {
                MetricTile(title: "Uscite", value: "\(pair.jointCount)",
                           caption: "attese \(Theme.decimal(pair.expectedCount, digits: 1))")
                MetricTile(title: "Rapporto", value: Theme.decimal(pair.lift, digits: 2) + "×",
                           tint: pair.lift > 1.15 ? Theme.high : .primary)
                MetricTile(title: "Ritardo", value: "\(pair.delay)")
                MetricTile(title: "Recenti", value: "\(pair.recentCount)")
            }

            Button {
                if expanded.contains(pair.id) { expanded.remove(pair.id) } else { expanded.insert(pair.id) }
            } label: {
                Label(expanded.contains(pair.id) ? "Nascondi" : "Perché?",
                      systemImage: expanded.contains(pair.id) ? "chevron.up" : "questionmark.circle")
                    .font(.subheadline)
            }

            if expanded.contains(pair.id) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pair.reasons, id: \.self) { reason in
                        Text("• " + reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func scoreMap(for numbers: [Int]) -> [Int: Double] {
        guard let context else { return [:] }
        var map: [Int: Double] = [:]
        for number in numbers { map[number] = context.score(of: number) }
        return map
    }

    private func generate() async {
        guard let viewModel else { return }
        await viewModel.generatePairs(limit: 10)
        let filter = viewModel.filter
        let weights = viewModel.strategy.weights
        let draws = app.draws(for: filter.game)
        context = await app.compute { AnalysisContext(filter: filter, allDraws: draws, weights: weights) }
    }
}
