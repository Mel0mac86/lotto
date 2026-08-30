import Foundation
import BackgroundTasks
import UserNotifications

/// Esito di un ciclo di aggiornamento automatico.
struct UpdateOutcome: Sendable {
    var newDraws: Int = 0
    var duplicates: Int = 0
    var sourcesChecked: Int = 0
    var failures: [String] = []
    var completedAt: Date = Date()

    var hasNewData: Bool { newDraws > 0 }
    var message: String {
        if !failures.isEmpty && newDraws == 0 {
            return "Aggiornamento non riuscito: \(failures.joined(separator: "; "))"
        }
        if newDraws == 0 { return "Nessuna nuova estrazione disponibile." }
        return "Nuova estrazione analizzata." + (newDraws > 1 ? " (\(newDraws) estrazioni aggiunte)" : "")
    }
}

/// **AGGIORNAMENTO AUTOMATICO**.
///
/// Pipeline: scarica → verifica duplicati → aggiorna database → ricalcola
/// statistiche, ranking, ritardi, ambi, terni e modelli → notifica l'utente.
@MainActor
final class AutoUpdateService {

    static let backgroundTaskIdentifier = "com.lottoaianalyzer.refresh"

    private let database: DatabaseService
    private let remote: RemoteDataService
    private let settings: AppSettings

    init(database: DatabaseService, settings: AppSettings, remote: RemoteDataService = RemoteDataService()) {
        self.database = database
        self.settings = settings
        self.remote = remote
    }

    /// Esegue l'intero ciclo di aggiornamento.
    @discardableResult
    func runUpdateCycle(notify: Bool = true) async -> UpdateOutcome {
        var outcome = UpdateOutcome()
        let sources = settings.remoteSources.filter(\.isEnabled)

        for source in sources {
            outcome.sourcesChecked += 1
            do {
                // 1. Scarica i nuovi dati.
                let records = try await remote.fetch(source)
                // 2-3. Verifica duplicati e aggiorna il database.
                let result = try database.insert(records, source: source.name)
                outcome.newDraws += result.inserted
                outcome.duplicates += result.duplicates
            } catch {
                outcome.failures.append("\(source.name): \(error.localizedDescription)")
            }
        }

        settings.lastUpdateCheck = Date()
        if outcome.hasNewData {
            // 4-9. Le statistiche, il ranking, i ritardi, gli ambi, i terni e i modelli
            // sono ricalcolati dai view model alla successiva lettura: invalidiamo le cache.
            AnalysisCache.shared.invalidateAll()
            settings.lastSuccessfulUpdate = Date()
        }

        // 10. Notifica.
        if notify && outcome.hasNewData && settings.notificationsEnabled {
            await postNotification(outcome: outcome)
        }
        return outcome
    }

    // MARK: - Notifiche

    func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            settings.notificationsEnabled = false
        }
    }

    private func postNotification(outcome: UpdateOutcome) async {
        let content = UNMutableNotificationContent()
        content.title = "Lotto AI Analyzer"
        content.body = outcome.message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Background refresh

    /// Registra il task di aggiornamento in background. Va chiamato all'avvio.
    static func registerBackgroundTask(handler: @escaping @Sendable (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handler(refreshTask)
        }
    }

    static func scheduleNextRefresh(after interval: TimeInterval = 6 * 3600) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Cache dei contesti di analisi, invalidata quando il database cambia.
final class AnalysisCache: @unchecked Sendable {
    static let shared = AnalysisCache()

    private let lock = NSLock()
    private var storage: [AnalysisFilter: AnalysisContext] = [:]
    private var generation = 0

    private init() {}

    func context(for filter: AnalysisFilter,
                 weights: ScoringWeights,
                 draws: @autoclosure () -> [DrawRecord]) -> AnalysisContext {
        lock.lock()
        if let cached = storage[filter], cached.weights == weights {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let context = AnalysisContext(filter: filter, allDraws: draws(), weights: weights)
        lock.lock()
        // Limite di memoria: la cache conserva al massimo 12 contesti.
        if storage.count >= 12 { storage.removeAll() }
        storage[filter] = context
        lock.unlock()
        return context
    }

    func invalidateAll() {
        lock.lock()
        storage.removeAll()
        generation += 1
        lock.unlock()
    }
}
