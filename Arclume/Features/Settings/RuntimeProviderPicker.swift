import SwiftUI

struct RuntimeProviderPicker: View {
    @ObservedObject var store: DownloadableResourceStore
    var showsDetails = true
    @EnvironmentObject private var globals: AppGlobals
    @State private var hovered: WineRuntimeProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDetails {
                ForEach(WineRuntimeProvider.allCases) { provider in
                    runtimeRow(provider)
                }
            } else {
                Picker("运行时", selection: $store.selectedProvider) {
                    ForEach(WineRuntimeProvider.allCases) { provider in
                        Text(provider.deliveryTitle).tag(provider)
                    }
                }
                .disabled(store.isBusy || store.isSwitchingRuntime)
                .accessibilityIdentifier("runtime-provider-picker")
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
            if !store.isBusy && !store.isSwitchingRuntime { store.selectedProvider = store.activeProvider }
        }
    }

    private func runtimeRow(_ provider: WineRuntimeProvider) -> some View {
        let selected = store.selectedProvider == provider
        let ready = provider == .arclume ? BundledWineRuntime.isCurrentRuntime() : NefinitaRuntime.isReady()
        let version = provider == .arclume ? BundledWineRuntime.runtimeVersion : NefinitaRuntime.version
        return Button {
            store.selectedProvider = provider
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider == .arclume ? "shippingbox" : "hammer")
                    .font(.system(size: 20)).frame(width: 28)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.title).font(.subheadline.weight(.semibold))
                    Text(provider == store.selectedProvider ? store.status.runtimeDetail :
                         "\(ready ? "已就绪" : "尚未安装") · \(version)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Text(provider == .arclume ? "预编译" : "本机编译")
                    .font(.caption).foregroundStyle(.secondary)
                if store.activeProvider == provider {
                    Text("使用中").font(.caption.weight(.medium)).foregroundStyle(.secondary)
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
        .disabled(store.isBusy || store.isSwitchingRuntime)
        .onHover { inside in hovered = inside ? provider : nil }
        .accessibilityIdentifier("runtime-choice-\(provider.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
