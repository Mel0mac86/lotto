import SwiftUI
import UIKit

/// Barra di selezione di gioco, ruota e periodo, condivisa da quasi tutte le schermate.
struct FilterBar: View {
    @Binding var filter: AnalysisFilter
    var showsGamePicker: Bool = true
    var showsWheelPicker: Bool = true
    var showsPeriodPicker: Bool = true
    var allowsAllWheels: Bool = true
    var onChange: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            if showsGamePicker {
                Picker("Gioco", selection: gameBinding) {
                    ForEach(GameType.allCases) { game in
                        Text(game.displayName).tag(game)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 10) {
                if showsWheelPicker && filter.game.usesWheels {
                    Menu {
                        Picker("Ruota", selection: wheelBinding) {
                            if allowsAllWheels {
                                Text("Tutte le ruote").tag(WheelScope.all)
                            }
                            ForEach(Wheel.allCases) { wheel in
                                Text(wheel.displayName).tag(WheelScope.single(wheel))
                            }
                        }
                    } label: {
                        pickerLabel(icon: "circle.grid.cross", text: filter.wheelScope.displayName)
                    }
                }

                if showsPeriodPicker {
                    Menu {
                        Picker("Periodo", selection: periodBinding) {
                            ForEach(AnalysisPeriod.allCases) { period in
                                Text(period.displayName).tag(period)
                            }
                        }
                    } label: {
                        pickerLabel(icon: "calendar", text: filter.period.displayName)
                    }
                }
            }
        }
    }

    private func pickerLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground, in: Capsule())
    }

    private var gameBinding: Binding<GameType> {
        Binding(get: { filter.game },
                set: { newValue in
                    filter.game = newValue
                    if !newValue.usesWheels { filter.wheelScope = .all }
                    else if case .all = filter.wheelScope { filter.wheelScope = .single(.bari) }
                    onChange?()
                })
    }

    private var wheelBinding: Binding<WheelScope> {
        Binding(get: { filter.wheelScope },
                set: { filter.wheelScope = $0; onChange?() })
    }

    private var periodBinding: Binding<AnalysisPeriod> {
        Binding(get: { filter.period },
                set: { filter.period = $0; onChange?() })
    }
}

/// Wrapper di `UIActivityViewController` per condividere i report esportati.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Bottone che genera ed esporta un report nei tre formati.
struct ExportMenu: View {
    let documentProvider: () -> ReportDocument?
    @State private var exportedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            ForEach(ReportFormat.allCases) { format in
                Button {
                    export(format)
                } label: {
                    Label(format.displayName, systemImage: format.icon)
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .sheet(item: Binding(get: { exportedURL.map { IdentifiableURL(url: $0) } },
                             set: { exportedURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Esportazione non riuscita",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func export(_ format: ReportFormat) {
        guard let document = documentProvider() else {
            errorMessage = "Non ci sono ancora risultati da esportare."
            return
        }
        do {
            exportedURL = try ReportExporter.export(document, format: format)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Riga con etichetta a sinistra e valore a destra.
struct LabeledValueRow: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}
