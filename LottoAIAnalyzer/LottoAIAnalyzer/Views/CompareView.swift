import SwiftUI

/// **CONFRONTO TRA COMBINAZIONI** — fino a 10 combinazioni affiancate.
struct CompareView: View {
    @Environment(AppModel.self) private var app
    var preselected: [GeneratedResult] = []

    @State private var saved: [SavedCombination] = []
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if !preselected.isEmpty {
                    comparisonTable(rows: preselected.map { Row($0) })
                }

                AppCard(title: "Combinazioni salvate", icon: "bookmark") {
                    if saved.isEmpty {
                        Text("Non hai ancora salvato combinazioni. Usa l'icona segnalibro nelle schermate di generazione.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(saved, id: \.combinationID) { item in
                            Button {
                                toggle(item)
                            } label: {
                                HStack {
                                    Image(systemName: selectedIDs.contains(item.combinationID) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedIDs.contains(item.combinationID) ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.formattedNumbers)
                                            .font(.subheadline.monospacedDigit())
                                        Text("\(item.game.displayName)\(item.wheel.map { " · \($0.displayName)" } ?? "") · \(item.strategy.displayName) · \(Theme.shortDateFormatter.string(from: item.createdAt))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    ScoreBadge(score: item.score, compact: true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                            Divider()
                        }
                        Text("Selezionate: \(selectedIDs.count)/10")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                let selectedRows = saved.filter { selectedIDs.contains($0.combinationID) }.map { Row($0) }
                if !selectedRows.isEmpty {
                    comparisonTable(rows: selectedRows)
                }

                DisclaimerBanner(text: Disclaimer.score, icon: "info.circle")
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Confronto")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { saved = app.savedCombinations() }
    }

    private func toggle(_ item: SavedCombination) {
        if selectedIDs.contains(item.combinationID) {
            selectedIDs.remove(item.id)
        } else if selectedIDs.count < 10 {
            selectedIDs.insert(item.id)
        }
    }

    private func comparisonTable(rows: [Row]) -> some View {
        AppCard(title: "Confronto", subtitle: "Combinazione · score · frequenza · ritardo · equilibrio", icon: "tablecells") {
            HStack {
                Text("Combinazione").frame(maxWidth: .infinity, alignment: .leading)
                Text("Score").frame(width: 46, alignment: .trailing)
                Text("Freq.").frame(width: 46, alignment: .trailing)
                Text("Rit.").frame(width: 46, alignment: .trailing)
                Text("Equil.").frame(width: 50, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()

            ForEach(rows) { row in
                HStack {
                    Text(row.numbers)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int(row.score.rounded()))")
                        .frame(width: 46, alignment: .trailing)
                        .foregroundStyle(Theme.color(forScore: row.score))
                    Text(row.frequency.map { "\(Int($0.rounded()))" } ?? "—")
                        .frame(width: 46, alignment: .trailing)
                    Text(row.delay.map { "\(Int($0.rounded()))" } ?? "—")
                        .frame(width: 46, alignment: .trailing)
                    Text(row.balance.map { "\(Int($0.rounded()))" } ?? "—")
                        .frame(width: 50, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    /// Riga del confronto, costruita da una combinazione generata o salvata.
    struct Row: Identifiable {
        let id: UUID
        let numbers: String
        let score: Double
        let frequency: Double?
        let delay: Double?
        let balance: Double?

        init(_ result: GeneratedResult) {
            id = result.id
            numbers = result.combination.formatted
            score = result.combination.score
            frequency = result.combination.components.frequency
            delay = result.combination.components.delay
            balance = result.combination.components.balance
        }

        init(_ saved: SavedCombination) {
            id = saved.combinationID
            numbers = saved.formattedNumbers
            score = saved.score
            frequency = nil
            delay = nil
            balance = nil
        }
    }
}
