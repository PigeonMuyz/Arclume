import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct JX3GPUProfileSettingsView: View {
    let configURL: URL?
    let isRuntimeActive: Bool
    @Binding var isApplying: Bool

    @State private var builtins: [JX3GPUProfile] = []
    @State private var snapshot = JX3GPUProfileStore.Snapshot(selected: nil, imported: [], pending: false)
    @State private var notice: String?
    @State private var errorMessage: String?

    private var profiles: [JX3GPUProfile] {
        var seen = Set<String>()
        return (builtins + snapshot.imported + [snapshot.selected].compactMap { $0 })
            .filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("显卡型号", selection: Binding(
                    get: { snapshot.selected?.id ?? "default" },
                    set: { change(to: $0) }
                )) {
                    Text("默认（不伪装）").tag("default")
                    ForEach(profiles) { profile in Text(profile.name).tag(profile.id) }
                }
                .disabled(isApplying || isRuntimeActive || configURL == nil)
                Menu {
                    Button("导入配置…", action: chooseProfile)
                    Button("恢复默认") { change(to: "default") }
                        .disabled(snapshot.selected == nil && !snapshot.pending)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("导入显卡配置或恢复默认")
                .accessibilityLabel("显卡配置操作")
                .disabled(isApplying || isRuntimeActive || configURL == nil)
            }
            .help("仅修改游戏显卡识别信息；选择默认可还原启用前的字段。")
            if isApplying {
                ProgressView("正在处理显卡配置…").controlSize(.small)
            } else if isRuntimeActive {
                Text("请先停止启动器和游戏。").font(.caption).foregroundStyle(.secondary)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .task(id: configURL) { await load() }
    }

    private func load() async {
        isApplying = true
        defer { isApplying = false }
        snapshot = .init(selected: nil, imported: [], pending: false)
        notice = nil
        errorMessage = nil
        do {
            if let configURL { snapshot = try await JX3GPUProfileStore.shared.snapshot(at: configURL) }
            if let url = BundledOnlineGameResources.resourceURL(named: "jx3-gpu-profiles.json") {
                builtins = try await Task.detached {
                    let profiles = try JSONDecoder().decode([JX3GPUProfile].self, from: Data(contentsOf: url))
                    for profile in profiles { try profile.validate() }
                    return profiles
                }.value
            }
            if snapshot.pending { errorMessage = "上次操作未完成，请重新选择预设或恢复默认。" }
        } catch { errorMessage = error.localizedDescription }
    }

    private func change(to id: String) {
        guard !isApplying, !isRuntimeActive, let configURL else { return }
        let profile = profiles.first { $0.id == id }
        guard id == "default" || profile != nil else { return }
        perform(at: configURL) {
            if let profile { return try await JX3GPUProfileStore.shared.apply(profile, at: configURL) }
            return try await JX3GPUProfileStore.shared.restore(at: configURL)
        }
    }

    private func chooseProfile() {
        guard !isApplying, !isRuntimeActive, let configURL else { return }
        let panel = NSOpenPanel()
        panel.title = "导入显卡配置"
        panel.message = "选择另一台机器的 machine_config.ini；只导入显卡字段和设备描述。"
        panel.allowedContentTypes = [UTType(filenameExtension: "ini") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        perform(at: configURL) {
            try await JX3GPUProfileStore.shared.importAndApply(from: source, at: configURL)
        }
    }

    private func perform(
        at config: URL,
        operation: @escaping @Sendable () async throws -> JX3GPUProfileStore.Snapshot
    ) {
        isApplying = true
        notice = nil
        errorMessage = nil
        Task { @MainActor in
            defer { isApplying = false }
            do {
                snapshot = try await operation()
                notice = snapshot.selected == nil ? "已恢复启用前的显卡信息。" : "已应用，下次启动游戏时生效。"
            } catch {
                errorMessage = error.localizedDescription
                if let current = try? await JX3GPUProfileStore.shared.snapshot(at: config) { snapshot = current }
            }
        }
    }
}
