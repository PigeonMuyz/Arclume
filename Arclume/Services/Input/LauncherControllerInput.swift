import Combine
import GameController

/// Owns only the launcher's shoulder-button bindings, not game input mappings.
@MainActor
final class LauncherControllerInput: ObservableObject {
    @Published private(set) var isConnected = false
    let steps = PassthroughSubject<Int, Never>()
    private var controllers: [GCController] = []
    private var observations = Set<AnyCancellable>()

    func start() {
        guard observations.isEmpty else { return }
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &observations)
        }
        refresh()
    }

    func stop() {
        observations.removeAll()
        unbind()
        isConnected = false
    }

    private func unbind() {
        for controller in controllers {
            controller.extendedGamepad?.leftShoulder.pressedChangedHandler = nil
            controller.extendedGamepad?.rightShoulder.pressedChangedHandler = nil
        }
        controllers = []
    }

    private func refresh() {
        unbind()
        controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        isConnected = !controllers.isEmpty
        for controller in controllers {
            controller.extendedGamepad?.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor [weak self] in self?.steps.send(-1) }
            }
            controller.extendedGamepad?.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor [weak self] in self?.steps.send(1) }
            }
        }
    }
}

enum LauncherControllerSelection {
    /// Wrap at either end, using the visible fallback if the saved item was removed.
    static func next(in ids: [String], selected: String?, step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        let index = selected.flatMap { ids.firstIndex(of: $0) } ?? 0
        let offset = step % ids.count
        return ids[(index + offset + ids.count) % ids.count]
    }
}
