import SwiftUI

/// **GENERA TERNO** — top 10 terni con indice statistico.
struct TriplesView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: GeneratorViewModel?
    @State private var context: AnalysisContext?
    @State private var expanded: Set<String> = []
    @State private var fullSearch = false
    let game: GameType

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    controls(viewModel)

                    if viewModel.isWorking {
                        ProgressOverlay(title: viewModel.progressLabel ?? "Elaborazione…")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.triples.isEmpty {
                        EmptyStateView(icon: "triangle",
                                       title: "Nessun terno calcolato",
                                       message: "Tocca «Genera terni» per esplorare le combinazioni di tre numeri.",
                                       actionTitle: "Genera terni") {
                            Task { await generate() }
                        }
                    } else {
                        Text("TOP \(viewModel.triples.count) TERNI")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(viewModel.triples.ranked()) { item in
                            tripleCard(rank: item.rank, triple: item.element)
                        }
                    }
                }
                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Terni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExportMenu {
                    guard let viewModel, let context, !viewModel.triples.isEmpty else { return nil }
                    return ReportBuilder.triplesReport(triples: viewModel.triples, context: context)
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

            Toggle("Enumerazione completa (117.480 terni)", isOn: $fullSearch)
                .font(.subheadline)
            Text(fullSearch
                 ? "Vengono valutate tutte le terne possibili: il calcolo richiede qualche secondo."
                 : "Vengono valutate le terne composte dai 45 numeri con indice statistico più alto.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                Task { await generate() }
            } label: {
                Label("Genera terni", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isWorking)
        }
    }

    private func tripleCard(rank: Int, triple: TripleResult) -> some View {
        AppCard {
            HStack(spacing: 12) {
                Text("\(rank).")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                CombinationRow(numbers: triple.numbers, scores: scoreMap(triple.numbers), size: 40)
                Spacer()
                ScoreBadge(score: triple.score)
            }

            HStack {
                MetricTile(title: "Terna uscita", value: "\(triple.jointCount)",
                           caption: "attese \(Theme.decimal(triple.expectedCount, digits: 2))")
                MetricTile(title: "Coppie interne", value: Theme.decimal(triple.averagePairCount))
                MetricTile(title: "Somma", value: "\(triple.sum)")
                MetricTile(title: "Pari/disp.", value: "\(triple.evenCount)/\(3 - triple.evenCount)")
            }

            Button {
                if expanded.contains(triple.id) { expanded.remove(triple.id) } else { expanded.insert(triple.id) }
            } label: {
                Label(expanded.contains(triple.id) ? "Nascondi" : "Perché?",
                      systemImage: expanded.contains(triple.id) ? "chevron.up" : "questionmark.circle")
                    .font(.subheadline)
            }

            if expanded.contains(triple.id) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(triple.reasons, id: \.self) { reason in
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

    private func scoreMap(_ numbers: [Int]) -> [Int: Double] {
        guard let context else { return [:] }
        var map: [Int: Double] = [:]
        for number in numbers { map[number] = context.score(of: number) }
        return map
    }

    private func generate() async {
        guard let viewModel else { return }
        await viewModel.generateTriples(limit: 10, poolSize: fullSearch ? 90 : 45)
        let filter = viewModel.filter
        let weights = viewModel.strategy.weights
        let draws = app.draws(for: filter.game)
        context = await app.compute { AnalysisContext(filter: filter, allDraws: draws, weights: weights) }
    }
}
