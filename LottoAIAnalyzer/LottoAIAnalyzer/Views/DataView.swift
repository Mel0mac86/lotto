import SwiftUI
import UniformTypeIdentifiers

/// **DATABASE STORICO** — import da file, sorgenti remote e aggiornamento automatico.
struct DataView: View {
    @Environment(AppModel.self) private var app
    @State private var isImporterPresented = false
    @State private var importGame: GameType = .lotto
    @State private var lastResult: ImportResult?
    @State private var isEditingSource = false
    @State private var draftSource = RemoteSource(name: "", urlString: "", game: .lotto)
    @State private var confirmDelete: GameType?

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .json, .plainText, .text, .data]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        return types
    }

    var body: some View {
        List {
            archiveSection
            importSection
            sourcesSection
            updateSection
            privacySection
        }
        .navigationTitle("Dati")
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: allowedTypes,
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .sheet(isPresented: $isEditingSource) {
            NavigationStack { sourceEditor }
        }
        .alert("Svuotare l'archivio?", isPresented: Binding(get: { confirmDelete != nil },
                                                           set: { if !$0 { confirmDelete = nil } })) {
            Button("Annulla", role: .cancel) { confirmDelete = nil }
            Button("Elimina", role: .destructive) {
                if let game = confirmDelete { app.deleteAll(game: game) }
                confirmDelete = nil
            }
        } message: {
            Text("Verranno eliminate tutte le estrazioni di \(confirmDelete?.displayName ?? "") memorizzate sul dispositivo. L'operazione non è reversibile.")
        }
    }

    // MARK: - Sezioni

    private var archiveSection: some View {
        Section("Archivio locale") {
            ForEach(GameType.allCases) { game in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(game.symbol) \(game.displayName)")
                            .font(.subheadline.weight(.medium))
                        Text(app.latestDate(for: game).map { "Aggiornato al \(Theme.dateFormatter.string(from: $0))" } ?? "Nessuna estrazione")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(app.drawCount(for: game))")
                        .font(.headline.monospacedDigit())
                }
                .swipeActions {
                    Button("Svuota", role: .destructive) { confirmDelete = game }
                }
            }
        }
    }

    private var importSection: some View {
        Section {
            Picker("Gioco del file", selection: $importGame) {
                ForEach(GameType.allCases) { game in Text(game.displayName).tag(game) }
            }
            Button {
                isImporterPresented = true
            } label: {
                Label("Importa da file (CSV, JSON, Excel)", systemImage: "square.and.arrow.down")
            }
            Button {
                Task { lastResult = await app.importSeedData() }
            } label: {
                Label("Carica dati di esempio simulati", systemImage: "wand.and.stars")
            }

            if let lastResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lastResult.summary)
                        .font(.caption)
                    ForEach(lastResult.errors, id: \.self) { error in
                        Text(error).font(.caption2).foregroundStyle(Theme.low)
                    }
                }
            }
        } header: {
            Text("Importazione")
        } footer: {
            Text("""
            Il file deve contenere una riga per estrazione. Colonne riconosciute: data, ruota, numero1…numero6 \
            (oppure n1…n6, o una singola colonna «numeri»), jolly, superstar. Le date sono accettate nei formati \
            gg/mm/aaaa, aaaa-mm-gg e ISO 8601. Le righe duplicate vengono ignorate automaticamente.

            I dati di esempio sono estrazioni SIMULATE, generate localmente: servono solo a provare l'interfaccia.
            """)
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(app.settings.remoteSources) { source in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(source.name.isEmpty ? source.urlString : source.name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(source.game.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(source.urlString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .swipeActions {
                    Button("Rimuovi", role: .destructive) {
                        app.settings.remoteSources.removeAll { $0.id == source.id }
                    }
                }
            }
            Button {
                draftSource = RemoteSource(name: "", urlString: "", game: importGame)
                isEditingSource = true
            } label: {
                Label("Aggiungi sorgente", systemImage: "plus")
            }
        } header: {
            Text("Sorgenti remote")
        } footer: {
            Text("""
            Inserisci l'indirizzo di un servizio che hai il diritto di utilizzare (API ufficiale, portale open data, \
            un tuo export). L'app riconosce automaticamente risposte in CSV, JSON o Excel. Nessuna sorgente è \
            preconfigurata e nessun dato personale viene inviato.
            """)
        }
    }

    private var updateSection: some View {
        Section {
            Toggle("Aggiornamento automatico in background",
                   isOn: Binding(get: { app.settings.autoUpdateEnabled },
                                 set: { app.settings.autoUpdateEnabled = $0 }))
            Toggle("Notifica «Nuova estrazione analizzata»",
                   isOn: Binding(get: { app.settings.notificationsEnabled },
                                 set: { newValue in
                                     app.settings.notificationsEnabled = newValue
                                     if newValue { Task { await app.updater.requestNotificationAuthorization() } }
                                 }))
            Button {
                Task { await app.runUpdate() }
            } label: {
                if app.isBusy {
                    HStack { ProgressView(); Text("Aggiornamento in corso…") }
                } else {
                    Label("Aggiorna adesso", systemImage: "arrow.clockwise")
                }
            }
            .disabled(app.isBusy || app.settings.remoteSources.isEmpty)

            if let outcome = app.lastUpdateOutcome {
                VStack(alignment: .leading, spacing: 3) {
                    Text(outcome.message).font(.caption)
                    if !outcome.failures.isEmpty {
                        ForEach(outcome.failures, id: \.self) { failure in
                            Text(failure).font(.caption2).foregroundStyle(Theme.low)
                        }
                    }
                }
            }
            if let last = app.settings.lastUpdateCheck {
                LabeledValueRow(label: "Ultimo controllo", value: Theme.dateFormatter.string(from: last))
            }
        } header: {
            Text("Aggiornamento")
        } footer: {
            Text("Dopo ogni aggiornamento riuscito l'app verifica i duplicati, aggiorna l'archivio e ricalcola statistiche, ranking, ritardi, ambi, terni e modelli.")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Text("""
            L'app funziona interamente sul dispositivo. Le estrazioni sono conservate in un database locale, \
            separato dalle preferenze dell'utente. Non è richiesta alcuna registrazione e nessun dato personale \
            viene raccolto o inviato. Le uniche connessioni di rete sono quelle verso le sorgenti che hai \
            configurato tu.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Editor sorgente

    private var sourceEditor: some View {
        Form {
            Section("Sorgente") {
                TextField("Nome", text: $draftSource.name)
                TextField("URL", text: $draftSource.urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Picker("Gioco", selection: $draftSource.game) {
                    ForEach(GameType.allCases) { game in Text(game.displayName).tag(game) }
                }
                Toggle("Attiva", isOn: $draftSource.isEnabled)
            }
            Section {
                Text("L'app esegue una richiesta GET all'indirizzo indicato e interpreta la risposta come CSV, JSON o Excel in base all'intestazione Content-Type o al contenuto.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Nuova sorgente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { isEditingSource = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    guard !draftSource.urlString.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    if draftSource.name.isEmpty { draftSource.name = draftSource.urlString }
                    app.settings.remoteSources.append(draftSource)
                    isEditingSource = false
                }
            }
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                var total = ImportResult()
                for url in urls {
                    total = total + (await app.importFile(at: url, defaultGame: importGame))
                }
                lastResult = total
            }
        case .failure(let error):
            lastResult = ImportResult(inserted: 0, duplicates: 0, rejected: 0, errors: [error.localizedDescription])
        }
    }
}
