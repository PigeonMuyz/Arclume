import AppKit
import SwiftUI
import Combine

enum LauncherTourTarget: String, CaseIterable { case add, sidebar, allGames, collapse, play, more, settings }

@MainActor final class LauncherTourRegistry: ObservableObject {
    @Published var rectangles: [LauncherTourTarget: CGRect] = [:]
    private var views: [LauncherTourTarget: [WeakView]] = [:]
    private struct WeakView { weak var value: NSView? }
    func register(_ view: NSView, for target: LauncherTourTarget) {
        var candidates = views[target, default: []].filter { $0.value != nil && $0.value !== view }
        candidates.append(WeakView(value: view))
        views[target] = candidates
    }
    func update(in window: NSWindow) {
        var next: [LauncherTourTarget: CGRect] = [:]
        for (target, candidates) in views {
            for entry in candidates.reversed() {
            guard let view = entry.value, let owner = view.window, owner === window, !view.isHiddenOrHasHiddenAncestor,
                  view.bounds.width > 1, view.bounds.height > 1 else { continue }
            let screen = owner.convertToScreen(view.convert(view.bounds, to: nil))
            next[target] = CGRect(x: screen.minX - window.frame.minX, y: window.frame.maxY - screen.maxY,
                                  width: screen.width, height: screen.height)
            break
            }
        }
        if next != rectangles { rectangles = next }
    }
}

private struct LauncherTourKey: EnvironmentKey { static let defaultValue: LauncherTourRegistry? = nil }
extension EnvironmentValues {
    var launcherTour: LauncherTourRegistry? {
        get { self[LauncherTourKey.self] }
        set { self[LauncherTourKey.self] = newValue }
    }
}
extension View {
    func launcherTourTarget(_ target: LauncherTourTarget) -> some View {
        background(LauncherTourAnchor(target: target))
    }
}
private struct LauncherTourAnchor: NSViewRepresentable {
    @Environment(\.launcherTour) private var registry
    let target: LauncherTourTarget
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { registry?.register(view, for: target) }
}

/// SwiftUI toolbar content lives outside the page's layout coordinate space.
/// A transparent child panel lets one SwiftUI tour cover both content and toolbar.
struct LauncherTourPresenter: NSViewRepresentable {
    let active: Bool
    let registry: LauncherTourRegistry
    let onFinish: (Bool, Bool) -> Void
    var offersSetup = true
    var startsAtSetup = false
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.requested = active
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator else { return }
            if coordinator.requested, let window = view.window {
                coordinator.show(in: window, registry: registry, offersSetup: offersSetup, startsAtSetup: startsAtSetup, onFinish: onFinish)
            } else { coordinator.close() }
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close() }

    @MainActor final class Coordinator {
        var requested = false
        private var panel: NSPanel?
        private var timer: Timer?
        func show(in parent: NSWindow, registry: LauncherTourRegistry, offersSetup: Bool, startsAtSetup: Bool, onFinish: @escaping (Bool, Bool) -> Void) {
            guard panel == nil else { return }
            let overlay = TourPanel(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = false
            overlay.isReleasedWhenClosed = false
            overlay.contentView = NSHostingView(rootView: LauncherTourOverlay(registry: registry, onFinish: onFinish,
                offersSetup: offersSetup, startsAtSetup: startsAtSetup))
            registry.update(in: parent)
            parent.addChildWindow(overlay, ordered: .above)
            overlay.makeKeyAndOrderFront(nil)
            panel = overlay
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self, weak parent] _ in
                MainActor.assumeIsolated {
                    guard let self, let parent, let panel = self.panel else { return }
                    if panel.frame != parent.frame { panel.setFrame(parent.frame, display: true) }
                    registry.update(in: parent)
                }
            }
        }
        func close() {
            timer?.invalidate(); timer = nil
            if let panel {
                let parent = panel.parent
                parent?.removeChildWindow(panel); panel.close()
                parent?.makeKey()
            }
            panel = nil
        }
    }
    private final class TourPanel: NSPanel { override var canBecomeKey: Bool { true } }
}
