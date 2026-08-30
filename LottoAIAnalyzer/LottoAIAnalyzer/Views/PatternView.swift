import SwiftUI

/// **🔍 TROVA PATTERN** — ricerca automatica di regolarità e anomalie.
struct PatternView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel: PatternViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let viewModel {
                    @Bindable var bindable = viewModel
                    AppCard {
                        FilterBar(filter: $bindable.filter)
                        Button {
                            Task { await viewModel.run() }
                        } label: {
                            Label("🔍 Trova pattern", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunning)
                    }

                    if viewModel.isRunning {
                        ProgressOverlay(title: "Ricerca di pattern…").frame(maxWidth: .infinity)
                    } else if viewModel.patterns.isEmpty {
                        EmptyStateView(icon: "magnifyingglass",
                                       title: "Nessuna ricerca eseguita",
                                       message: "Scegli gioco, ruota e periodo, poi avvia la ricerca.")
                    } else {
                        summary(viewModel)
                        ForEach(viewModel.grouped) { group in
                            AppCard(title: group.category.rawValue, icon: icon(for: group.category)) {
                                ForEach(group.items) { pattern in
                                    patternRow(pattern)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                DisclaimerBanner()
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .navigationTitle("Trova pattern")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel == nil { viewModel = PatternViewModel(app: app) } }
    }

    private func summary(_ viewModel: PatternViewModel) -> some View {
        AppCard(title: "Sintesi", icon: "list.bullet.clipboard") {
            HStack {
                MetricTile(title: "Pattern esaminati", value: "\(viewModel.patterns.count)")
                MetricTile(title: "Da approfondire", value: "\(viewModel.noteworthyCount)",
                           tint: viewModel.noteworthyCount > 0 ? Theme.medium : Theme.high)
            }
            Text(viewModel.noteworthyCount == 0
                 ? "Nessun pattern si discosta dalla casualità in modo statisticamente rilevante."
                 : "Alcuni pattern superano le soglie di significatività. Ricorda che, testando migliaia di combinazioni, alcuni scostamenti compaiono per puro caso.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func patternRow(_ pattern: DetectedPattern) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(pattern.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if pattern.isNoteworthy {
                    Text("da approfondire")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.medium)
                }
            }
            Text(pattern.detail)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let test = pattern.test {
                Text("Statistica: \(Theme.decimal(test.statistic, digits: 2))\(test.degreesOfFreedom.map { " · gdl \($0)" } ?? "") · p = \(Theme.decimal(test.pValue, digits: 4))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(pattern.assessment)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
    }

    private func icon(for category: DetectedPattern.Category) -> String {
        switch category {
        case .frequency: return "chart.bar"
        case .coOccurrence: return "link"
        case .delay: return "hourglass"
        case .distribution: return "square.grid.3x3"
        case .temporal: return "calendar"
        case .cluster: return "circle.hexagongrid"
        case .anomaly: return "exclamationmark.triangle"
        }
    }
}
