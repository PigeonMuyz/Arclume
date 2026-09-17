import SwiftUI

struct WineWarmupOption: View {
    var showsStatus = true
    @AppStorage(WineWarmupService.defaultsKey, store: UserDefaults(suiteName: suiteName)) private var enabled = false
    @AppStorage(WineWarmupService.targetsKey, store: UserDefaults(suiteName: suiteName)) private var selectedTargets = "[]"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("随 Arclume 启动并预热 Wine", isOn: $enabled)
                .accessibilityIdentifier("wine-prewarm-toggle")
            if enabled {
                ForEach(BundledWineRuntime.prefixURL == BundledWineRuntime.standardSteamPrefixURL ? [.steam] : WineWarmupTarget.allCases) { target in
                    HStack {
                        Toggle(BundledWineRuntime.prefixURL == BundledWineRuntime.standardSteamPrefixURL ? "ALBottles · 所有 Windows 应用" : target.title, isOn: Binding(
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
            }
        }
        .onChange(of: enabled) { _, _ in
            guard !ArclumeTestEnvironment.isTesting else { return }
            // New opt-ins start with an explicit empty selection; only existing
            // enabled preferences are migrated by ContentView at startup.
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
