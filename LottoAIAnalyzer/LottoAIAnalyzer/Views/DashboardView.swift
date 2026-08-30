import SwiftUI

/// Home page con le card di accesso rapido a tutte le sezioni.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedGame: GameType = .lotto

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                statusCard

                Picker("Gioco", selection: $selectedGame) {
                    ForEach(GameType.allCases) { game in
                        Text("\(game.symbol) \(game.displayName)").tag(game)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: columns, spacing: 12) {
                    tile("📊", "Analisi", "Frequenze, ritardi, distribuzioni") {
                        AnalysisView(game: selectedGame)
                    }
                    tile("🔥", "Numeri hot", "Frequenza recente in crescita") {
                        HotColdView(game: selectedGame, initialFilter: .hot)
                    }
                    tile("❄️", "Numeri cold", "Frequenza recente in calo") {
                        HotColdView(game: selectedGame, initialFilter: .cold)
                    }
                    tile("⏳", "Ritardatari", "Estrazioni dall'ultima uscita") {
                        DelayView(game: selectedGame)
                    }
                    tile("🔗", "Ambi", "Top coppie statisticamente interessanti") {
                        PairsView(game: selectedGame)
                    }
                    tile("🔺", "Terni", "Top combinazioni di tre numeri") {
                        TriplesView(game: selectedGame)
                    }
                    tile("🎯", selectedGame == .lotto ? "Genera cinquina" : "Genera sestina",
                         "Quattro modalità di generazione") {
                        QuintupleView(game: selectedGame)
                    }
                    if selectedGame == .lotto {
                        tile("🎡", "Multi-ruota", "Segnali comuni a più ruote") {
                            MultiWheelView()
                        }
                    }
                    tile("🧪", "Backtest", "Simulazione walk-forward") {
                        BacktestView()
                    }
                    tile("🤖", "AI Analyst", "Modelli sperimentali e validazione") {
                        MLView()
                    }
                    tile("🔍", "Trova pattern", "Ricorrenze e anomalie") {
                        PatternView()
                    }
                    tile("🎲", "Monte Carlo", "Confronto con la casualità") {
                        MonteCarloView()
                    }
                    tile("⚖️", "Confronto", "Fino a 10 combinazioni") {
                        CompareView()
                    }
                    tile("📥", "Dati", "Import, sorgenti e aggiornamento") {
                        DataView()
                    }
                }

                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Lotto AI Analyzer")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { selectedGame = app.settings.defaultGame }
    }

    // MARK: - Sottoviste

    private var statusCard: some View {
        AppCard(title: "Archivio locale", icon: "internaldrive") {
            HStack(alignment: .top) {
                MetricTile(title: "Lotto",
                           value: "\(app.drawCount(for: .lotto))",
                           caption: app.latestDate(for: .lotto).map { "Al \(Theme.shortDateFormatter.string(from: $0))" } ?? "Nessun dato")
                MetricTile(title: "SuperEnalotto",
                           value: "\(app.drawCount(for: .superenalotto))",
                           caption: app.latestDate(for: .superenalotto).map { "Al \(Theme.shortDateFormatter.string(from: $0))" } ?? "Nessun dato")
            }
            if !app.hasAnyData {
                NavigationLink {
                    DataView()
                } label: {
                    Label("Importa lo storico per iniziare", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                }
                .padding(.top, 4)
            } else if let last = app.settings.lastSuccessfulUpdate {
                Text("Ultimo aggiornamento: \(Theme.dateFormatter.string(from: last))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tile<Destination: View>(_ emoji: String,
                                         _ title: String,
                                         _ subtitle: String,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(emoji).font(.title2)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
