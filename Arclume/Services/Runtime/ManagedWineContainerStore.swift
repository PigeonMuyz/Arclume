import Combine
import Foundation

@MainActor
final class ManagedWineContainerStore: ObservableObject {
    @Published private(set) var containers: [ManagedWineContainer] = []
    @Published private(set) var preparingID: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    let repository: ManagedWineContainerRepository

    init(defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard,
         root: URL = ARCLUME_SUPPORT_FOLDER_URL) {
        repository = .init(defaults: defaults, root: root)
    }

    func refresh() {
        do { containers = try repository.containers(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func create(name: String, provider: WineRuntimeProvider) -> Bool {
        guard preparingID == nil else { return false }
        do {
            try repository.create(name: name, provider: provider)
            refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    @discardableResult
    func rename(id: String, name: String) -> Bool {
        guard preparingID == nil else { return false }
        do {
            try repository.rename(id: id, name: name)
            refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func initialize(id: String) async {
        guard preparingID == nil, !ArclumeTestEnvironment.isTesting else { return }
        guard !DownloadableResourceStore.shared.isBusy, !DownloadableResourceStore.shared.isSwitchingRuntime else {
            error = "正在准备或切换运行时，请稍后重试。"
            return
        }
        preparingID = id
        progress = 0
        error = nil
        message = "正在准备容器…"
        defer { preparingID = nil; message = nil }
        do {
            let repository = repository
            _ = try await Task.detached(priority: .userInitiated) { [weak self] in
                return try BundledWineRuntime.prepareManagedContainer(id: id, repository: repository) { fraction, label in
                    Task { @MainActor [weak self] in
                        guard let self, self.preparingID == id else { return }
                        self.progress = fraction
                        self.message = label
                    }
                }
            }.value
            refresh()
        } catch { self.error = error.localizedDescription }
    }
}
