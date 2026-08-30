import SwiftUI
import Charts

/// **NUMERI RITARDATARI** — dashboard dei ritardi.
struct DelayView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: AnalysisViewModel?
    let game: GameType

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    @Bindable var bindable = viewModel
                    FilterBar(filter: $bindable.filter, showsGamePicker: false) {
                        Task { await viewModel.load() }
                    }
                }

                if let context = viewModel?.context, !context.isEmpty {
                    chart(context)
                    table(context)
                } else if viewModel?.isLoading == true {
                    ProgressOverlay(title: "Calcolo dei ritardi…")
                } else {
                    EmptyStateView(icon: "hourglass",
                                   title: "Nessun dato",
                                   message: "Importa lo storico per calcolare i ritardi.")
                }

                DisclaimerBanner(text: Disclaimer.delay, icon: "exclamationmark.triangle")
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Ritardatari")
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

    private func chart(_ context: AnalysisContext) -> some View {
        AppCard(title: "Ritardo attuale rispetto al massimo storico", icon: "chart.bar.xaxis") {
            let items = Array(HotColdEngine.overdueRanking(context: context, limit: 20))
            Chart(items) { item in
                BarMark(x: .value("Percentuale", min(item.delayRatio * 100, 100)),
                        y: .value("Numero", Theme.number(item.number)))
                .foregroundStyle(Theme.color(forScore: min(item.delayRatio * 100, 100)))
            }
            .chartXScale(domain: 0...100)
            .frame(height: 380)
            Text("La barra indica quanto il ritardo attuale si avvicina al massimo storico del numero.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func table(_ context: AnalysisContext) -> some View {
        AppCard(title: "Tutti i numeri", subtitle: "Ordinati per ritardo attuale", icon: "list.number") {
            HStack {
                Text("N.").frame(width: 32, alignment: .leading)
                Text("Ultima").frame(width: 64, alignment: .leading)
                Text("Rit.").frame(width: 44, alignment: .trailing)
                Text("Medio").frame(width: 52, alignment: .trailing)
                Text("Max").frame(width: 44, alignment: .trailing)
                Spacer()
                Text("%").frame(width: 44, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()

            ForEach(HotColdEngine.overdueRanking(context: context, limit: 90)) { item in
                NavigationLink {
                    NumberDetailView(number: item.number, filter: context.filter)
                } label: {
                    HStack {
                        Text(Theme.number(item.number))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .frame(width: 32, alignment: .leading)
                        Text(item.lastSeen.map { Theme.shortDateFormatter.string(from: $0) } ?? "mai")
                            .frame(width: 64, alignment: .leading)
                        Text("\(item.currentDelay)").frame(width: 44, alignment: .trailing)
                        Text(Theme.decimal(item.averageDelay)).frame(width: 52, alignment: .trailing)
                        Text("\(item.maxDelay)").frame(width: 44, alignment: .trailing)
                        Spacer()
                        Text(Theme.decimal(min(item.delayRatio * 100, 999), digits: 0))
                            .frame(width: 44, alignment: .trailing)
                            .foregroundStyle(item.delayRatio >= 1 ? Theme.low : .primary)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}
