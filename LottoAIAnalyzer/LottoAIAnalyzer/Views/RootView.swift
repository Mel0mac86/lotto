import SwiftUI

/// Contenitore principale: dashboard, analisi, generatori, laboratorio, impostazioni.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Tab = .dashboard

    enum Tab: Hashable {
        case dashboard, analysis, generate, lab, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                .tag(Tab.dashboard)

            NavigationStack { AnalysisHomeView() }
                .tabItem { Label("Analisi", systemImage: "chart.bar.xaxis") }
                .tag(Tab.analysis)

            NavigationStack { SmartGeneratorView() }
                .tabItem { Label("Genera", systemImage: "wand.and.stars") }
                .tag(Tab.generate)

            NavigationStack { LabHomeView() }
                .tabItem { Label("Laboratorio", systemImage: "flask") }
                .tag(Tab.lab)

            NavigationStack { SettingsView() }
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.accentColor)
    }
}

/// Schermata mostrata al primo avvio con l'avvertenza obbligatoria.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @State private var isImporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lotto AI Analyzer")
                        .font(.largeTitle.weight(.bold))
                    Text("Motore di analisi statistica per Lotto e SuperEnalotto")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                AppCard(title: "Che cosa fa questa app", icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Importa e archivia lo storico delle estrazioni sul dispositivo.")
                        bullet("Calcola frequenze, ritardi, co-occorrenze, distribuzioni e trend.")
                        bullet("Genera combinazioni con un indice statistico e ne spiega le motivazioni.")
                        bullet("Verifica ogni strategia con backtest walk-forward, Monte Carlo e test statistici.")
                    }
                }

                AppCard(title: "Che cosa NON fa", icon: "exclamationmark.triangle") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Non prevede l'estrazione successiva.")
                        bullet("Non aumenta la probabilità matematica di vincita.")
                        bullet("Non presenta l'indice statistico come una probabilità di uscita.")
                    }
                }

                DisclaimerBanner()

                Button {
                    app.settings.hasAcceptedDisclaimer = true
                } label: {
                    Text("Ho capito, iniziamo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .background(Theme.pageBackground)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}
