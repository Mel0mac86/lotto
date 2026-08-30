import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct LottoAIAnalyzerApp: App {

    @State private var appModel: AppModel
    private let container: ModelContainer

    init() {
        let schema = Schema([Draw.self, SavedCombination.self])
        let container: ModelContainer
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Se il contenitore su disco non è apribile (per esempio dopo una migrazione
            // fallita) si riparte in memoria: l'app resta usabile e l'utente può reimportare.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? (try! ModelContainer(for: Draw.self))
        }
        self.container = container

        let model = AppModel(container: container)
        _appModel = State(initialValue: model)

        BackgroundRefreshCoordinator.shared.attach(model)
        AutoUpdateService.registerBackgroundTask { task in
            BackgroundRefreshCoordinator.handle(task)
        }
        AutoUpdateService.scheduleNextRefresh()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appModel.settings.hasAcceptedDisclaimer {
                    RootView()
                } else {
                    WelcomeView()
                }
            }
            .environment(appModel)
            .modelContainer(container)
            .preferredColorScheme(appModel.settings.appearance.colorScheme)
            .task { await startUp() }
        }
    }

    private func startUp() async {
        if appModel.settings.notificationsEnabled {
            await appModel.updater.requestNotificationAuthorization()
        }
        if appModel.settings.autoUpdateEnabled && !appModel.settings.remoteSources.isEmpty {
            await appModel.runUpdate()
        }
    }
}

/// Collega il task di aggiornamento in background al modello dell'app.
@MainActor
final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()
    private weak var appModel: AppModel?

    private init() {}

    func attach(_ model: AppModel) { appModel = model }

    /// Punto di ingresso chiamato da `BGTaskScheduler` (fuori dal main actor).
    nonisolated static func handle(_ task: BGAppRefreshTask) {
        // Ripianifica subito: se l'esecuzione fallisce, il ciclo non si interrompe.
        AutoUpdateService.scheduleNextRefresh()
        let work = Task { @MainActor in
            guard let model = BackgroundRefreshCoordinator.shared.appModel else {
                task.setTaskCompleted(success: false)
                return
            }
            let outcome = await model.updater.runUpdateCycle()
            if outcome.hasNewData { model.reloadDraws() }
            task.setTaskCompleted(success: outcome.failures.isEmpty)
        }
        task.expirationHandler = { work.cancel() }
    }
}
