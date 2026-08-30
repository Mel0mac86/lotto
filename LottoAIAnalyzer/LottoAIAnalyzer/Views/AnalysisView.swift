import SwiftUI
import Charts

/// **ANALISI ANNUALE / MULTI-ANNO** con tabelle e grafici interattivi.
struct AnalysisView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: AnalysisViewModel?
    @State private var mode: Mode = .period
    @State private var selectedYear: Int?
    @State private var comparisonRows: [YearComparisonRow] = []
    @State private var selectedYears: Set<Int> = []
    @State private var sortField: SortField = .score
    @State private var isComparing = false

    let game: GameType

    enum Mode: String, CaseIterable, Identifiable {
        case period = "Periodo"
        case year = "Anno"
        case comparison = "Confronto anni"
        var id: String { rawValue }
    }

    enum SortField: String, CaseIterable, Identifiable {
        case score = "Indice"
        case frequency = "Uscite"
        case delay = "Ritardo"
        case number = "Numero"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                controls

                if let viewModel, viewModel.isLoading {
                    ProgressOverlay(title: "Calcolo statistiche…")
                        .frame(maxWidth: .infinity)
                } else if let context = viewModel?.context, !context.isEmpty {
                    summaryCard(context)
                    switch mode {
                    case .period, .year:
                        frequencyChart(context)
                        delayChart(context)
                        distributionCharts(context)
                        numbersTable(context)
                    case .comparison:
                        comparisonSection
                    }
                } else {
                    EmptyStateView(icon: "tray",
                                   title: "Nessuna estrazione",
                                   message: "Importa lo storico di \(game.displayName) per vedere le analisi.")
                }

                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Analisi \(game.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExportMenu {
                    guard let context = viewModel?.context else { return nil }
                    return ReportBuilder.analysisReport(context: context, topCount: 90)
                }
            }
        }
        .task { await setUp() }
        .onChange(of: mode) {
            // Passare da "Periodo" ad "Anno" cambia il filtro: le statistiche vanno ricalcolate.
            Task { await reload() }
        }
    }

    // MARK: - Sezioni

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Modalità", selection: $mode) {
                ForEach(Mode.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)

            if let viewModel {
                @Bindable var bindable = viewModel
                FilterBar(filter: $bindable.filter,
                          showsGamePicker: false,
                          showsPeriodPicker: mode == .period) {
                    Task { await reload() }
                }
            }

            if mode == .year {
                let years = viewModel?.availableYears ?? []
                if years.isEmpty {
                    Text("Nessun anno disponibile.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Anno", selection: Binding(get: { selectedYear ?? years.first ?? 0 },
                                                      set: { selectedYear = $0; Task { await reload() } })) {
                        ForEach(years, id: \.self) { year in Text(String(year)).tag(year) }
                    }
                    .pickerStyle(.menu)
                }
            }

            if mode == .comparison {
                comparisonPicker
            }
        }
    }

    private var comparisonPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seleziona gli anni da confrontare")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel?.availableYears ?? [], id: \.self) { year in
                        Button {
                            if selectedYears.contains(year) { selectedYears.remove(year) } else { selectedYears.insert(year) }
                        } label: {
                            Text(String(year))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedYears.contains(year) ? Color.accentColor.opacity(0.18) : Theme.cardBackground,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                Task { await runComparison() }
            } label: {
                if isComparing { ProgressView() } else { Text("Confronta") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedYears.count < 2 || isComparing)
        }
    }

    private func summaryCard(_ context: AnalysisContext) -> some View {
        AppCard(title: "Periodo analizzato", icon: "calendar.badge.clock") {
            HStack {
                MetricTile(title: "Estrazioni", value: "\(context.drawCount)")
                MetricTile(title: "Dal", value: context.statistics.firstDate.map { Theme.shortDateFormatter.string(from: $0) } ?? "—")
                MetricTile(title: "Al", value: context.statistics.lastDate.map { Theme.shortDateFormatter.string(from: $0) } ?? "—")
            }
            HStack {
                MetricTile(title: "Somma media", value: Theme.decimal(context.sumMean))
                MetricTile(title: "Più frequente",
                           value: context.statistics.sortedByFrequency.first.map { Theme.number($0.number) } ?? "—")
                MetricTile(title: "Ritardo max",
                           value: context.statistics.sortedByDelay.first.map { "\($0.currentDelay)" } ?? "—")
            }
        }
    }

    private func frequencyChart(_ context: AnalysisContext) -> some View {
        AppCard(title: "Frequenza dei numeri", subtitle: "Uscite osservate contro la media attesa", icon: "chart.bar") {
            let items = context.game.numberRange.compactMap { context.statistics.numbers[$0] }
            let expected = Double(context.drawCount * context.game.drawnCount) / 90
            Chart {
                ForEach(items) { item in
                    BarMark(x: .value("Numero", item.number),
                            y: .value("Uscite", item.occurrences))
                    .foregroundStyle(Theme.color(forScore: context.score(of: item.number)))
                }
                RuleMark(y: .value("Media", expected))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("media attesa")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: 1...90)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
            .frame(height: 200)
        }
    }

    private func delayChart(_ context: AnalysisContext) -> some View {
        AppCard(title: "Ritardo attuale", subtitle: "Estrazioni trascorse dall'ultima uscita", icon: "hourglass") {
            let items = context.game.numberRange.compactMap { context.statistics.numbers[$0] }
            Chart(items) { item in
                BarMark(x: .value("Numero", item.number),
                        y: .value("Ritardo", item.currentDelay))
                .foregroundStyle(item.isOverdue ? Theme.low : Theme.neutral.opacity(0.6))
            }
            .chartXScale(domain: 1...90)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
            .frame(height: 160)
        }
    }

    @ViewBuilder
    private func distributionCharts(_ context: AnalysisContext) -> some View {
        if let viewModel {
            AppCard(title: "Distribuzione delle somme", icon: "sum") {
                Chart(viewModel.sumDistribution) { item in
                    BarMark(x: .value("Somma", item.sum), y: .value("Estrazioni", item.count))
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                }
                .frame(height: 140)
            }

            AppCard(title: "Pari / dispari per estrazione", icon: "circle.lefthalf.filled") {
                Chart(viewModel.parityDistribution) { item in
                    BarMark(x: .value("Pari", item.key), y: .value("Estrazioni", item.count))
                        .foregroundStyle(Theme.medium)
                }
                .frame(height: 130)
            }

            AppCard(title: "Distribuzione per decine e unità", icon: "square.grid.3x3") {
                Chart {
                    ForEach(viewModel.decadeDistribution) { item in
                        BarMark(x: .value("Decina", item.decadeLabel),
                                y: .value("Uscite", item.count))
                        .foregroundStyle(Theme.high.opacity(0.75))
                    }
                }
                .frame(height: 140)

                Chart {
                    ForEach(viewModel.unitDistribution) { item in
                        BarMark(x: .value("Unità", String(item.key)),
                                y: .value("Uscite", item.count))
                        .foregroundStyle(Color.accentColor.opacity(0.6))
                    }
                }
                .frame(height: 120)
            }

            if context.filter.describesAllWheels && context.game.usesWheels {
                AppCard(title: "Heatmap ruote × numeri", subtitle: "Intensità relativa delle uscite", icon: "square.grid.3x3.fill") {
                    Chart(viewModel.heatmapWheelsByNumber()) { cell in
                        RectangleMark(x: .value("Numero", cell.number),
                                      y: .value("Ruota", cell.wheel.shortCode))
                        .foregroundStyle(Color.accentColor.opacity(0.15 + cell.value * 0.85))
                    }
                    .chartXScale(domain: 1...90)
                    .frame(height: 220)
                }
            }
        }
    }

    private func numbersTable(_ context: AnalysisContext) -> some View {
        AppCard(title: "Tabella completa", subtitle: "Numero · uscite · frequenza · ritardo · percentile · indice", icon: "tablecells") {
            Picker("Ordina per", selection: $sortField) {
                ForEach(SortField.allCases) { field in Text(field.rawValue).tag(field) }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                HStack {
                    Text("N.").frame(width: 34, alignment: .leading)
                    Text("Usc.").frame(width: 44, alignment: .trailing)
                    Text("Freq.").frame(width: 56, alignment: .trailing)
                    Text("Rit.").frame(width: 44, alignment: .trailing)
                    Text("Perc.").frame(width: 48, alignment: .trailing)
                    Spacer()
                    Text("Indice").frame(width: 54, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

                Divider()

                ForEach(sortedScores(context)) { item in
                    NavigationLink {
                        NumberDetailView(number: item.number, filter: context.filter)
                    } label: {
                        HStack {
                            Text(Theme.number(item.number))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .frame(width: 34, alignment: .leading)
                            Text("\(item.statistics.occurrences)")
                                .frame(width: 44, alignment: .trailing)
                            Text(Theme.decimal(item.statistics.frequency * 100, digits: 2))
                                .frame(width: 56, alignment: .trailing)
                            Text("\(item.statistics.currentDelay)")
                                .frame(width: 44, alignment: .trailing)
                            Text(Theme.decimal(item.statistics.frequencyPercentile, digits: 0))
                                .frame(width: 48, alignment: .trailing)
                            Spacer()
                            ScoreBadge(score: item.score, compact: true)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private var comparisonSection: some View {
        AppCard(title: "Confronto fra anni",
                subtitle: "Scostamento standardizzato dell'anno più recente rispetto agli altri selezionati",
                icon: "arrow.left.arrow.right") {
            if comparisonRows.isEmpty {
                Text("Seleziona almeno due anni e tocca «Confronta».")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let years = selectedYears.sorted()
                HStack {
                    Text("N.").frame(width: 34, alignment: .leading)
                    ForEach(years, id: \.self) { year in
                        Text(String(year).suffix(2))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Text("Δσ").frame(width: 52, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()

                ForEach(comparisonRows.prefix(30)) { row in
                    HStack {
                        Text(Theme.number(row.number))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .frame(width: 34, alignment: .leading)
                        ForEach(years, id: \.self) { year in
                            Text("\(row.byYear[year] ?? 0)")
                                .font(.caption.monospacedDigit())
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Text(Theme.decimal(row.deviation, digits: 2))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(abs(row.deviation) > 2 ? Theme.low : .secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    Divider()
                }

                Text("Δσ è lo scostamento dell'anno più recente rispetto alla media degli altri anni, espresso in deviazioni standard. Valori oltre ±2 sono attesi per puro caso in alcuni numeri su novanta.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Logica

    private func sortedScores(_ context: AnalysisContext) -> [NumberScore] {
        let scores = context.rankedNumbers
        switch sortField {
        case .score: return scores
        case .frequency: return scores.sorted { $0.statistics.occurrences > $1.statistics.occurrences }
        case .delay: return scores.sorted { $0.statistics.currentDelay > $1.statistics.currentDelay }
        case .number: return scores.sorted { $0.number < $1.number }
        }
    }

    private func setUp() async {
        if viewModel == nil {
            var filter = app.settings.defaultFilter()
            filter.game = game
            if !game.usesWheels { filter.wheelScope = .all }
            viewModel = AnalysisViewModel(app: app, filter: filter)
        }
        selectedYear = viewModel?.availableYears.first
        await reload()
    }

    private func reload() async {
        guard let viewModel else { return }
        var filter = viewModel.filter
        filter.game = game
        filter.calendarYear = mode == .year ? (selectedYear ?? viewModel.availableYears.first) : nil
        await viewModel.update(filter: filter)
    }

    private func runComparison() async {
        guard let viewModel else { return }
        isComparing = true
        comparisonRows = await viewModel.comparison(years: selectedYears.sorted())
        isComparing = false
    }
}
