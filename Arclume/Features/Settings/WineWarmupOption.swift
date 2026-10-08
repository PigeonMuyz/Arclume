import SwiftUI

struct WineWarmupOption: View {
    var showsStatus = true
    @AppStorage(WineWarmupService.defaultsKey, store: UserDefaults(suiteName: suiteName)) private var enabled = false
    @AppStorage(WineWarmupService.targetsKey, store: UserDefaults(suiteName: suiteName)) private var selectedTargets = "[]"
    @State private var availableTargets: [WineWarmupTarget] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("运行环境随 Arclume 启动", isOn: $enabled)
                .accessibilityIdentifier("wine-prewarm-toggle")
            if enabled && availableTargets.count > 1 {
                ForEach(availableTargets) { target in
                    HStack {
                        Toggle(target.prefix.lastPathComponent, isOn: Binding(
                            get: { WineWarmupTarget.decode(selectedTargets).contains(target) },
                            set: { selected in
                                var targets = WineWarmupTarget.decode(selectedTargets)
                                if selected { targets.insert(target) } else { targets.remove(target) }
                                selectedTargets = WineWarmupTarget.encode(targets)
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("wine-prewarm-\(target.rawValue)")
                        if showsStatus && WineWarmupTarget.decode(selectedTargets).contains(target) {
                            WineWarmupStatus(session: WineWarmupService.shared.session(for: target))
                        }
                    }
                    .padding(.leading, 20)
                }
            } else if enabled && showsStatus, let target = availableTargets.first {
                WineWarmupStatus(session: WineWarmupService.shared.session(for: target))
            }
        }
        .onAppear { availableTargets = WineWarmupTarget.available }
        .onReceive(NotificationCenter.default.publisher(for: .arclumeWinePrefixReady)) { _ in
            availableTargets = WineWarmupTarget.available
        }
        .onChange(of: enabled) { _, _ in
            guard !ArclumeTestEnvironment.isTesting else { return }
            // Keep explicit choices for multiple containers; a sole container
            // is selected by the service without rewriting saved preferences.
            if UserDefaults(suiteName: suiteName)?.object(forKey: WineWarmupService.targetsKey) == nil {
                selectedTargets = "[]"
            }
            WineWarmupService.shared.preferenceChanged()
        }
        .onChange(of: selectedTargets) { _, _ in
            guard !ArclumeTestEnvironment.isTesting else { return }
            WineWarmupService.shared.preferenceChanged(retry: false)
        }
    }
}

private struct WineWarmupStatus: View {
    @ObservedObject var session: WineWarmupSession

    var body: some View {
        Text(session.status).font(.footnote).foregroundStyle(.secondary)
    }
}
