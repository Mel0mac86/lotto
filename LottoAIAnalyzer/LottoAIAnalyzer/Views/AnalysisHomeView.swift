import SwiftUI

/// Indice della sezione "Analisi".
struct AnalysisHomeView: View {
    @Environment(AppModel.self) private var app
    @State private var game: GameType = .lotto

    var body: some View {
        List {
            Section {
                Picker("Gioco", selection: $game) {
                    ForEach(GameType.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section("Statistiche") {
                link("Analisi annuale e multi-anno", "calendar", AnalysisView(game: game))
                link("Numeri ritardatari", "hourglass", DelayView(game: game))
                link("Caldi, freddi e ritardatari", "thermometer.medium", HotColdView(game: game, initialFilter: .hot))
            }

            Section("Combinazioni") {
                link("Ambi", "link", PairsView(game: game))
                link("Terni", "triangle", TriplesView(game: game))
                link(game == .lotto ? "Cinquina AI" : "Sestina AI", "target", QuintupleView(game: game))
                if game == .lotto {
                    link("Analisi multi-ruota", "circle.grid.cross", MultiWheelView())
                }
            }

            Section("Verifica") {
                link("Trova pattern", "magnifyingglass", PatternView())
                link("Monte Carlo", "dice", MonteCarloView())
                link("Backtest", "flask", BacktestView())
            }

            Section {
                DisclaimerBanner()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Analisi")
        .onAppear { game = app.settings.defaultGame }
    }

    private func link<Destination: View>(_ title: String, _ icon: String, _ destination: Destination) -> some View {
        NavigationLink {
            destination
        } label: {
            Label(title, systemImage: icon)
        }
    }
}
