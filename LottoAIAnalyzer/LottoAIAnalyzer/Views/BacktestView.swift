import SwiftUI
import Charts

/// **BACKTESTING** walk-forward e sistema di validazione.
struct BacktestView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: BacktestViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    configurationCard(viewModel)

                    if viewModel.isRunning {
                        ProgressOverlay(title: "Simulazione walk-forward in corso…")
                            .frame(maxWidth: .infinity)
                    }

                    if let message = viewModel.errorMessage {
                        AppCard {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(Theme.low)
                        }
                    }

                    if let result = viewModel.result, result.drawsEvaluated > 0 {
                        verdictCard(result)
                        summaryCard(result)
                        equityChart(viewModel)
                        hitChart(viewModel)
                        stepsCard(result)
                    }

                    if let validation = viewModel.validation {
                        validationCard(validation)
                    }
                }

                AppCard(title: "Protezione dal data leakage", icon: "lock.shield") {
                    Text(Disclaimer.backtest)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A ogni passo il motore ricostruisce le statistiche applicando un limite temporale stretto: nessuna estrazione con data uguale o successiva a quella simulata entra nel calcolo di frequenze, ritardi o co-occorrenze.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Backtest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ExportMenu {
                    guard let viewModel, let result = viewModel.result else { return nil }
                    return ReportBuilder.backtestReport(result: result, validation: viewModel.validation)
                }
            }
        }
        .task { if viewModel == nil { viewModel = BacktestViewModel(app: app) } }
    }

    // MARK: - Card

    private func configurationCard(_ viewModel: BacktestViewModel) -> some View {
        AppCard(title: "Configurazione", icon: "slider.horizontal.3") {
            Picker("Gioco", selection: Binding(get: { viewModel.game }, set: { viewModel.game = $0 })) {
                ForEach(GameType.allCases) { game in Text(game.displayName).tag(game) }
            }
            .pickerStyle(.segmented)

            if viewModel.game.usesWheels {
                Picker("Ruota", selection: Binding(get: { viewModel.wheel }, set: { viewModel.wheel = $0 })) {
                    ForEach(Wheel.allCases) { wheel in Text(wheel.displayName).tag(wheel) }
                }
                .pickerStyle(.menu)
            }

            Picker("Strategia", selection: Binding(get: { viewModel.kind }, set: { viewModel.kind = $0 })) {
                ForEach(BacktestStrategyKind.allCases) { kind in Text(kind.displayName).tag(kind) }
            }
            .pickerStyle(.menu)

            if viewModel.kind == .quintuples {
                Picker("Modalità", selection: Binding(get: { viewModel.mode }, set: { viewModel.mode = $0 })) {
                    ForEach(QuintupleMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                }
                .pickerStyle(.menu)
            }

            Picker("Finestra storica", selection: Binding(get: { viewModel.lookback }, set: { viewModel.lookback = $0 })) {
                ForEach(AnalysisPeriod.allCases) { period in Text(period.displayName).tag(period) }
            }
            .pickerStyle(.menu)

            DatePicker("Dal", selection: Binding(get: { viewModel.startDate }, set: { viewModel.startDate = $0 }),
                       displayedComponents: .date)
            DatePicker("Al", selection: Binding(get: { viewModel.endDate }, set: { viewModel.endDate = $0 }),
                       displayedComponents: .date)

            Stepper("Giocate per estrazione: \(viewModel.playsPerDraw)",
                    value: Binding(get: { viewModel.playsPerDraw }, set: { viewModel.playsPerDraw = $0 }),
                    in: 1...10)
                .font(.subheadline)

            HStack {
                Text("Posta per giocata")
                    .font(.subheadline)
                Spacer()
                TextField("1", value: Binding(get: { viewModel.stake }, set: { viewModel.stake = $0 }),
                          format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }

            HStack {
                Button {
                    Task { await viewModel.run() }
                } label: {
                    Label("Esegui backtest", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning)

                Button {
                    Task { await viewModel.runValidation() }
                } label: {
                    Label("Valida", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRunning)
            }
        }
    }

    private func verdictCard(_ result: BacktestResult) -> some View {
        AppCard(title: "Verdetto", icon: "checkmark.seal") {
            Text(result.verdict)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(result.significance.interpretation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryCard(_ result: BacktestResult) -> some View {
        AppCard(title: "Risultati teorici", icon: "eurosign.circle") {
            HStack {
                MetricTile(title: "Estrazioni", value: "\(result.drawsEvaluated)")
                MetricTile(title: "Giocate", value: "\(result.strategy.totalPlays)")
                MetricTile(title: "Centrate", value: "\(result.strategy.winningPlays)",
                           caption: Theme.percent(result.strategy.hitRate * 100, digits: 2))
            }
            Divider().padding(.vertical, 4)
            LabeledValueRow(label: "Costo teorico", value: Theme.currency(result.strategy.totalCost))
            LabeledValueRow(label: "Vincite teoriche", value: Theme.currency(result.strategy.totalWinnings))
            LabeledValueRow(label: "Saldo teorico", value: Theme.currency(result.strategy.net),
                            tint: result.strategy.net >= 0 ? Theme.high : Theme.low)
            LabeledValueRow(label: "ROI teorico", value: Theme.percent(result.strategy.roi),
                            tint: result.strategy.roi >= 0 ? Theme.high : Theme.low)
            Divider().padding(.vertical, 4)
            Text("Baseline casuale")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LabeledValueRow(label: "Giocate centrate", value: "\(result.baseline.winningPlays) (\(Theme.percent(result.baseline.hitRate * 100, digits: 2)))")
            LabeledValueRow(label: "ROI baseline", value: Theme.percent(result.baseline.roi))

            ForEach([2, 3, 4, 5, 6], id: \.self) { matched in
                if result.strategy.hits(matched) > 0 || result.baseline.hits(matched) > 0 {
                    LabeledValueRow(label: sorteName(matched),
                                    value: "\(result.strategy.hits(matched)) (baseline \(result.baseline.hits(matched)))")
                }
            }
        }
    }

    private func sorteName(_ matched: Int) -> String {
        switch matched {
        case 2: return "Ambi centrati"
        case 3: return "Terni centrati"
        case 4: return "Quaterne centrate"
        case 5: return "Cinquine centrate"
        case 6: return "Sestine centrate"
        default: return "\(matched) numeri"
        }
    }

    private func equityChart(_ viewModel: BacktestViewModel) -> some View {
        AppCard(title: "Saldo teorico cumulato", icon: "chart.line.uptrend.xyaxis") {
            Chart(viewModel.equityCurve) { point in
                LineMark(x: .value("Data", point.date), y: .value("Saldo", point.value))
                    .foregroundStyle(point.value >= 0 ? Theme.high : Theme.low)
                AreaMark(x: .value("Data", point.date), y: .value("Saldo", point.value))
                    .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                                                     startPoint: .top, endPoint: .bottom))
            }
            .frame(height: 170)
            Text("Il saldo include il costo di ogni giocata simulata e le vincite calcolate con i moltiplicatori impostati.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func hitChart(_ viewModel: BacktestViewModel) -> some View {
        AppCard(title: "Numeri indovinati: strategia contro baseline", icon: "chart.bar") {
            Chart(viewModel.hitDistribution) { bucket in
                BarMark(x: .value("Indovinati", String(bucket.matched)),
                        y: .value("Giocate", bucket.strategy))
                .position(by: .value("Serie", "Strategia"))
                .foregroundStyle(Color.accentColor)

                BarMark(x: .value("Indovinati", String(bucket.matched)),
                        y: .value("Giocate", bucket.baseline))
                .position(by: .value("Serie", "Baseline"))
                .foregroundStyle(Theme.neutral.opacity(0.5))
            }
            .frame(height: 180)
        }
    }

    private func stepsCard(_ result: BacktestResult) -> some View {
        AppCard(title: "Dettaglio estrazioni simulate", subtitle: "Ultime 40", icon: "list.bullet.rectangle") {
            ForEach(Array(result.steps.suffix(40).reversed())) { step in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Theme.shortDateFormatter.string(from: step.date))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("miglior risultato: \(step.bestMatch)")
                            .font(.caption2)
                            .foregroundStyle(step.bestMatch >= 2 ? Theme.high : .secondary)
                    }
                    Text("Estratti: " + step.drawnNumbers.map { Theme.number($0) }.joined(separator: " "))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Giocate: " + step.plays.map { $0.map { Theme.number($0) }.joined(separator: "-") }.joined(separator: "  "))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
    }

    private func validationCard(_ validation: ValidationReport) -> some View {
        AppCard(title: "Sistema di validazione", icon: "checkmark.shield") {
            Text(validation.verdict)
                .font(.subheadline.weight(validation.isEdgeDemonstrated ? .semibold : .regular))
                .foregroundStyle(validation.isEdgeDemonstrated ? Theme.high : Theme.low)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)

            ForEach(validation.checks) { check in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(check.passed ? Theme.high : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.name).font(.subheadline.weight(.medium))
                        Text(check.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 3)
            }

            if !validation.walkForwardFolds.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Finestre walk-forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(validation.walkForwardFolds) { fold in
                    LabeledValueRow(
                        label: "\(Theme.shortDateFormatter.string(from: fold.start)) → \(Theme.shortDateFormatter.string(from: fold.end))",
                        value: "\(Theme.percent(fold.hitRate * 100, digits: 2)) vs \(Theme.percent(fold.baselineHitRate * 100, digits: 2))",
                        tint: fold.difference > 0 ? Theme.high : Theme.low)
                }
            }
        }
    }
}
