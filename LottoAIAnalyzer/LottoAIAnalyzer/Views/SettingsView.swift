import SwiftUI

/// Impostazioni: aspetto, pesi dello scoring, moltiplicatori, dati, informazioni.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var weights: ScoringWeights = .balanced

    var body: some View {
        Form {
            Section("Aspetto") {
                Picker("Tema", selection: Binding(get: { app.settings.appearance },
                                                  set: { app.settings.appearance = $0 })) {
                    ForEach(AppSettings.AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Valori predefiniti") {
                Picker("Gioco", selection: Binding(get: { app.settings.defaultGame },
                                                   set: { app.settings.defaultGame = $0 })) {
                    ForEach(GameType.allCases) { game in Text(game.displayName).tag(game) }
                }
                Picker("Ruota", selection: Binding(get: { app.settings.defaultWheel },
                                                   set: { app.settings.defaultWheel = $0 })) {
                    ForEach(Wheel.allCases) { wheel in Text(wheel.displayName).tag(wheel) }
                }
                Picker("Periodo", selection: Binding(get: { app.settings.defaultPeriod },
                                                     set: { app.settings.defaultPeriod = $0 })) {
                    ForEach(AnalysisPeriod.allCases) { period in Text(period.displayName).tag(period) }
                }
            }

            Section {
                weightSlider("Frequenza", value: $weights.frequency)
                weightSlider("Recenza", value: $weights.recency)
                weightSlider("Ritardo", value: $weights.delay)
                weightSlider("Trend", value: $weights.trend)
                weightSlider("Co-occorrenza", value: $weights.coOccurrence)
                weightSlider("Stabilità", value: $weights.stability)

                HStack {
                    Button("Bilanciati") { weights = .balanced; apply() }
                    Spacer()
                    Button("Frequenza") { weights = .frequencyFocused; apply() }
                    Spacer()
                    Button("Ritardo") { weights = .delayFocused; apply() }
                    Spacer()
                    Button("Trend") { weights = .trendFocused; apply() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } header: {
                Text("Pesi dello Statistical Number Score")
            } footer: {
                Text("I pesi vengono normalizzati automaticamente, così l'indice resta sempre fra 0 e 100. L'indice descrive il comportamento passato di un numero e non è una probabilità di uscita.")
            }

            Section {
                ForEach([1, 2, 3, 4, 5, 6], id: \.self) { matched in
                    payoutField(matched: matched)
                }
            } header: {
                Text("Moltiplicatori teorici per il backtest")
            } footer: {
                Text("Per il Lotto i valori predefiniti sono i moltiplicatori ufficiali lordi per posta unitaria su una ruota. Per il SuperEnalotto le vincite sono a totalizzatore e variano a ogni concorso: i valori sono indicativi e modificabili.")
            }

            Section("Dati") {
                NavigationLink { DataView() } label: {
                    Label("Archivio, import e sorgenti", systemImage: "internaldrive")
                }
            }

            Section {
                Text(Disclaimer.primary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Disclaimer.explainer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Avvertenze")
            }

            Section("Informazioni") {
                LabeledValueRow(label: "Versione", value: Bundle.main.appVersion)
                LabeledValueRow(label: "Estrazioni Lotto", value: "\(app.drawCount(for: .lotto))")
                LabeledValueRow(label: "Estrazioni SuperEnalotto", value: "\(app.drawCount(for: .superenalotto))")
            }
        }
        .navigationTitle("Impostazioni")
        .onAppear { weights = app.settings.weights }
    }

    private func weightSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(Theme.decimal(value.wrappedValue * 100, digits: 0) + "%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1, step: 0.05) { editing in
                if !editing { apply() }
            }
        }
    }

    private func payoutField(matched: Int) -> some View {
        let game = app.settings.defaultGame
        let binding = Binding<Double>(
            get: { app.settings.payouts(for: game).multipliers[matched] ?? 0 },
            set: { newValue in
                var table = app.settings.payouts(for: game)
                table.multipliers[matched] = newValue
                if game == .lotto { app.settings.lottoPayouts = table }
                else { app.settings.superenalottoPayouts = table }
            })
        return HStack {
            Text("\(matched) numeri (\(game.displayName))")
                .font(.subheadline)
            Spacer()
            TextField("0", value: binding, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }

    private func apply() {
        app.settings.weights = weights
        AnalysisCache.shared.invalidateAll()
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
