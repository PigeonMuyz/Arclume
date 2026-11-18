import SwiftUI

struct RuntimeProviderPicker: View {
    enum Presentation {
        case settings, onboarding
    }

    @ObservedObject var store: DownloadableResourceStore
    var presentation: Presentation = .settings
    private var showsDetails: Bool { presentation == .settings }
    @EnvironmentObject private var globals: AppGlobals
    @State private var hovered: WineRuntimeProvider?
    @State private var activating = false
    @State private var activationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WineRuntimeProvider.allCases) { provider in
                runtimeRow(provider)
            }

            if activating {
                ProgressView(value: store.progress) {
                    Text(store.message ?? "正在切换运行时…")
                }.font(.footnote)
            }
            if let activationError {
                Text(activationError).font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsDetails && store.selectedProvider == .nefinita {
                if !NefinitaRuntime.isReady() {
                    HStack {
                        Button("检查构建环境") { Task { await store.checkBuildEnvironment() } }
                    }.disabled(store.isBusy || store.isSwitchingRuntime)
                    if let report = store.buildEnvironment {
                        Text(report.isReady ? "构建工具已就绪" : "尚缺：\(report.missing.joined(separator: "、"))")
                            .font(.footnote).foregroundStyle(report.isReady ? Color.green : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if report.missing.contains("Rosetta 2") {
                            Text("请先通过 macOS 安装 Rosetta 2，再重新检查。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let log = store.buildLog { Link("查看构建日志", destination: log) }
            }
        }
        .onChange(of: store.activeProvider) { _, provider in
            globals.selectedBottle = provider.prefixURL().absoluteString
            NotificationCenter.default.post(name: .arclumeWinePrefixReady, object: provider.prefixURL())
        }
        .onDisappear {
            // An unconfirmed choice must not affect later automatic resource preparation.
            if !activating && !store.isBusy && !store.isSwitchingRuntime { store.selectedProvider = store.activeProvider }
        }
    }

    private func runtimeRow(_ provider: WineRuntimeProvider) -> some View {
        let selected = store.selectedProvider == provider
        let ready: Bool
        let detail: String
        let delivery: String
        let icon: String
        switch provider {
        case .arclume:
            ready = BundledWineRuntime.isCurrentRuntime()
            detail = showsDetails ? (selected ? store.status.runtimeDetail :
                "\(ready ? "已就绪" : "尚未安装") · \(BundledWineRuntime.runtimeVersion)") : "下载预编译版本"
            delivery = "预编译"
            icon = "shippingbox"
        case .nefinita:
            ready = NefinitaRuntime.isReady()
            detail = showsDetails ? (selected ? store.status.runtimeDetail :
                "\(ready ? "已就绪" : "尚未安装") · \(NefinitaRuntime.version)") : "在本机编译"
            delivery = "本机编译"
            icon = "hammer"
        }
        return Button {
            guard !activating, !store.isBusy, !store.isSwitchingRuntime else { return }
            activationError = nil
            store.selectedProvider = provider
            // Onboarding only records a choice; its primary action starts preparation or activation.
            guard presentation == .settings, ready else { return }
            activating = true
            Task {
                defer { activating = false }
                do {
                    try await store.activateSelection()
                } catch {
                    store.selectedProvider = store.activeProvider
                    activationError = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20)).frame(width: 28)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.title).font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if showsDetails {
                    Text(delivery)
                        .font(.caption).foregroundStyle(.secondary)
                    if store.activeProvider == provider {
                        Text("使用中").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(hovered == provider ? 0.06 : 0.025),
                        in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(activating || store.isBusy || store.isSwitchingRuntime)
        .onHover { inside in hovered = inside ? provider : nil }
        .accessibilityIdentifier("runtime-choice-\(provider.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
