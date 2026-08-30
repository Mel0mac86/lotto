import SwiftUI

/// **ANALISI MULTI-RUOTA**: numeri, ambi, terni e cinquina su tutte le ruote.
struct MultiWheelView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: GeneratorViewModel?
    @State private var section: Section = .numbers

    enum Section: String, CaseIterable, Identifiable {
        case numbers = "Numeri"
        case pairs = "Ambi"
        case triples = "Terni"
        case combination = "Cinquina"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    controls(viewModel)

                    if viewModel.isWorking {
                        ProgressOverlay(title: viewModel.progressLabel ?? "Analisi in corso…")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.multiWheelNumbers.isEmpty {
                        EmptyStateView(icon: "circle.grid.cross",
                                       title: "Analisi non ancora eseguita",
                                       message: "Il calcolo esamina tutte e undici le ruote e richiede qualche secondo.",
                                       actionTitle: "Analizza tutte le ruote") {
                            Task { await viewModel.loadMultiWheel() }
                        }
                    } else {
                        Picker("Sezione", selection: $section) {
                            ForEach(Section.allCases) { item in Text(item.rawValue).tag(item) }
                        }
                        .pickerStyle(.segmented)

                        switch section {
                        case .numbers: numbersSection(viewModel)
                        case .pairs: setsSection(viewModel.multiWheelPairs, title: "TOP AMBI MULTI-RUOTA")
                        case .triples: setsSection(viewModel.multiWheelTriples, title: "TOP TERNI MULTI-RUOTA")
                        case .combination: combinationSection(viewModel)
                        }
                    }
                }
                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Multi-ruota")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let model = GeneratorViewModel(app: app)
                model.game = .lotto
                model.useAllWheels = true
                viewModel = model
            }
        }
    }

    private func controls(_ viewModel: GeneratorViewModel) -> some View {
        AppCard {
            Picker("Periodo", selection: Binding(get: { viewModel.period }, set: { viewModel.period = $0 })) {
                ForEach(AnalysisPeriod.allCases) { period in Text(period.displayName).tag(period) }
            }
            .pickerStyle(.menu)
            Button {
                Task { await viewModel.loadMultiWheel() }
            } label: {
                Label("Aggiorna analisi", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isWorking)
        }
    }

    private func numbersSection(_ viewModel: GeneratorViewModel) -> some View {
        AppCard(title: "Numeri con segnali su più ruote",
                subtitle: "Numero · ruote · frequenza complessiva · indice",
                icon: "circle.grid.cross") {
            HStack {
                Text("N.").frame(width: 32, alignment: .leading)
                Text("Ruote").frame(maxWidth: .infinity, alignment: .leading)
                Text("Usc.").frame(width: 52, alignment: .trailing)
                Text("Indice").frame(width: 54, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()

            ForEach(viewModel.multiWheelNumbers) { item in
                HStack {
                    Text(Theme.number(item.number))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(width: 32, alignment: .leading)
                    Text(item.wheelCodes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.totalOccurrences)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 52, alignment: .trailing)
                    ScoreBadge(score: item.score, compact: true)
                        .frame(width: 54, alignment: .trailing)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private func setsSection(_ items: [MultiWheelSet], title: String) -> some View {
        VStack(spacing: Theme.stackSpacing) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if items.isEmpty {
                Text("Nessun risultato disponibile per il periodo selezionato.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(items.ranked()) { entry in
                let item = entry.element
                AppCard {
                    HStack {
                        Text("\(entry.rank).")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        CombinationRow(numbers: item.numbers, size: 40)
                        Spacer()
                        ScoreBadge(score: item.score)
                    }
                    HStack {
                        MetricTile(title: "Ruote", value: "\(item.wheelCount)")
                        MetricTile(title: "Uscite", value: "\(item.totalJointCount)")
                        MetricTile(title: "Recenti", value: "\(item.recentJointCount)")
                        MetricTile(title: "Rit. medio", value: Theme.decimal(item.averageDelay))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(item.reasons, id: \.self) { reason in
                            Text("• " + reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func combinationSection(_ viewModel: GeneratorViewModel) -> some View {
        VStack(spacing: Theme.stackSpacing) {
            if let result = viewModel.multiWheelCombination {
                AppCard(title: "CINQUINA MULTI-RUOTA", icon: "target") {
                    CombinationRow(numbers: result.combination.numbers, size: 48)
                    HStack {
                        Text("Indice statistico")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ScoreBadge(score: result.combination.score)
                    }
                    if !viewModel.multiWheelSignals.isEmpty {
                        Text("Ruote su cui il sistema ha trovato i segnali più forti: "
                             + viewModel.multiWheelSignals.map(\.displayName).joined(separator: ", ") + ".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.combination.reasons, id: \.self) { reason in
                            Text("• " + reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    NavigationLink {
                        ResultDetailView(result: result, context: nil) { viewModel.save(result) }
                    } label: {
                        Label("Dettaglio completo", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline)
                    }
                }
            } else {
                Text("Nessuna combinazione multi-ruota generata: servono numeri con segnali su più ruote nel periodo selezionato.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
