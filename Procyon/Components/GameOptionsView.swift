//
//  GameOptionsView.swift
//  Procyon
//
//  Created by Italo Mandara on 12/02/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GameOptionsView: View {
    @Binding var game: Game?
    @EnvironmentObject var gameOptions: GameOptions
    @EnvironmentObject private var appGlobals: AppGlobals
    @State private var isAutoConfiguring = false
    @State private var autoConfigErrorMessage: String?
    @State private var isApplyingJX3Preset = false
    @State private var jx3PresetMessage: String?
    @State private var jx3PresetErrorMessage: String?

    private var isJX3Game: Bool {
        guard let game else { return false }
        return OnlineGameMode.isJX3(game)
    }

    private var gameID: String {
        guard let game else { return "" }
        return game.steamAppID != 0
            ? String(describing: game.steamAppID)
            : String(describing: game.id)
    }

    private var gameOptionsKey: String {
        namespacedKey(
            "GameOptions",
            OnlineGameMode.gameOptionsIdentifier(for: game!)
        )
    }

    var preferredMaxFrameRate: String {
        $gameOptions.dxmtPreferredMaxFrameRate.wrappedValue < 20.0
            ? L10n.string("Disabled")
            : "\($gameOptions.dxmtPreferredMaxFrameRate.wrappedValue)"
    }

    var d3dMaxFPS: String {
        $gameOptions.d3dMaxFPS.wrappedValue < 20.0
            ? L10n.string("Disabled")
            : "\($gameOptions.d3dMaxFPS.wrappedValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.format("Game ID: %@", gameID))
                .font(.footnote)
                .foregroundStyle(.procyonBrightGray)

            if isJX3Game {
                onlineOptionsForm
            } else {
                standardOptionsForm
            }
        }
        .padding()
        .onAppear(perform: loadOptions)
    }

    private var onlineOptionsForm: some View {
        Form {
            VStack(alignment: .leading, spacing: 20) {
                Section("剑网3运行选项") {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .trailing, spacing: 12) {
                            DropDown(
                                options: OnlineGameMode.onlineGraphicsBackends,
                                label: "图形后端",
                                value: $gameOptions.cxGraphicsBackend
                            )
                            .onChange(of: gameOptions.cxGraphicsBackend) { _, backend in
                                gameOptions.d3dMtl4Enabled = backend == "d3dmetal4"
                            }

                            Divider()
                            TextField("启动参数", text: $gameOptions.gameArguments)
                            TextField("环境变量", text: $gameOptions.envVariables)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 12) {
                            Toggle("Metal HUD", isOn: $gameOptions.mtlHudEnabled)
                            Toggle("MSync", isOn: $gameOptions.wineMSync)
                            Toggle("DLSS3 帧生成 Beta", isOn: $gameOptions.dlssFrameGenerationEnabled)
                                .help("启动前将剑网3的 DLSS 配置写为 2；关闭时恢复为 1。")
                            Toggle(
                                "检测到游戏本体后关闭启动器",
                                isOn: $gameOptions.closeLauncherWhenGameStarts
                            )
                            .help("检测到 JX3ClientX64.exe 后，仅关闭 SeasunGame.exe。")
                        }
                    }
                }

                jx3PresetSection

                optionsActions(includeAutoConfigure: false)
            }
        }
        .controlSize(.small)
        .formStyle(.columns)
        .toggleStyle(.switch)
    }

    private var jx3PresetSection: some View {
        Section("剑网3画质预设") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("导入推荐预设", systemImage: "sparkles") {
                        importRecommendedJX3Preset()
                    }
                    .disabled(isApplyingJX3Preset)

                    Button("从文件导入", systemImage: "square.and.arrow.down") {
                        chooseJX3Preset()
                    }
                    .disabled(isApplyingJX3Preset)

                    if isApplyingJX3Preset {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .buttonStyle(.bordered)

                Text("导入你在游戏外调整好的 config.ini。导入会直接替换当前配置，不会保存备份；DLSS 默认写入 1，启动时按上面的 Beta 开关切换为 2。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let jx3PresetMessage {
                    Text(jx3PresetMessage)
                        .font(.footnote)
                        .foregroundStyle(.procyonBrightGray)
                }
                if let jx3PresetErrorMessage {
                    Text(jx3PresetErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var standardOptionsForm: some View {
        Form {
            VStack(alignment: .leading, spacing: 20) {
                Section(L10n.string("Generic options")) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .trailing) {
                            if !game!.isNative {
                                DropDown(
                                    options: cxGraphicsBackend,
                                    label: L10n.string("Graphics Backend"),
                                    value: $gameOptions.cxGraphicsBackend
                                )
                            }
                            Divider()
                            TextField(L10n.string("Game arguments"), text: $gameOptions.gameArguments)
                            TextField(L10n.string("Env variables"), text: $gameOptions.envVariables)
                            if !game!.isNative {
                                Divider()
                                Text(L10n.string("32Bits options"))
                                Toggle(L10n.string("Use DX9"), isOn: $gameOptions.dx9PatchEnabled)
                                    .onChange(of: gameOptions.dx9PatchEnabled) { _, newValue in
                                        if newValue {
                                            gameOptions.cxGraphicsBackend = "wine"
                                        }
                                    }
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Toggle(L10n.string("Metal HUD"), isOn: $gameOptions.mtlHudEnabled)
                            Toggle(L10n.string("Advertise AVX"), isOn: $gameOptions.advertiseAVX)
                            if !game!.isNative {
                                Toggle(L10n.string("MSync"), isOn: $gameOptions.wineMSync)
                                Toggle(L10n.string("Enable SDL"), isOn: $gameOptions.enableSDL)
                                Toggle(L10n.string("Disable Hidraw"), isOn: $gameOptions.disableHidraw)
                                Divider()
                                Text(L10n.string("Vulkan options"))
                                Toggle(L10n.string("Enable UE4 Hack"), isOn: $gameOptions.ue4Hack)
                                Toggle(L10n.string("MTL arg. buffers"), isOn: $gameOptions.mvkArgBuff)
                                DropDown(
                                    options: cxVulkanBackend,
                                    label: L10n.string("Vulkan library"),
                                    value: $gameOptions.vulkanLib
                                )
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }

                if gameOptions.cxGraphicsBackend == "dxmt" {
                    Divider()
                    Section(L10n.string("DXMT Options")) {
                        VStack {
                            Text(L10n.format("Preferred maximum frame rate: %@", preferredMaxFrameRate))
                            Slider(
                                value: $gameOptions.dxmtPreferredMaxFrameRate,
                                in: 19...240,
                                step: 1.0
                            )
                            .help(L10n.string("Use a value below 20 to let the game choose the frame rate."))
                        }

                        Toggle(L10n.string("MetalFX spatial upscaling"), isOn: $gameOptions.dxmtMetalFXSpatial)
                            .help(L10n.string("Enables MetalFX spatial upscaling when the game supports it."))
                            .onChange(of: gameOptions.dxmtMetalFXSpatial) { _, newValue in
                                if !newValue {
                                    gameOptions.dxmtMetalSpatialUpscaleFactor = 1.0
                                }
                            }

                        if gameOptions.dxmtMetalFXSpatial {
                            VStack {
                                Text(L10n.format(
                                    "MetalFX spatial upscale factor: %@",
                                    String(gameOptions.dxmtMetalSpatialUpscaleFactor)
                                ))
                                Slider(
                                    value: $gameOptions.dxmtMetalSpatialUpscaleFactor,
                                    in: 1.0...2.0,
                                    step: 0.125
                                )
                                .help(L10n.string("Enables MetalFX spatial upscaling when the game supports it."))
                            }
                        }
                    }
                }

                if gameOptions.cxGraphicsBackend == "d3dmetal4" {
                    Divider()
                    Section(L10n.string("D3DMetal Options")) {
                        Toggle(L10n.string("Metal 4 Backend"), isOn: $gameOptions.d3dMtl4Enabled)
                            .help(L10n.string("Uses the Metal 4 graphics backend when supported by CrossOver."))
                            .disabled(OSVersion < 27)
                            .opacity(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 ? 0.5 : 1.0)
                        VStack {
                            Text(L10n.format("Preferred maximum frame rate: %@", d3dMaxFPS))
                            Slider(
                                value: $gameOptions.d3dMaxFPS,
                                in: 19...240,
                                step: 1.0
                            )
                            .help(L10n.string("Use a value below 20 to let the game choose the frame rate."))
                        }
                    }
                }

                optionsActions(includeAutoConfigure: true)
            }
        }
        .controlSize(.small)
        .formStyle(.columns)
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private func optionsActions(includeAutoConfigure: Bool) -> some View {
        HStack {
            Button(L10n.string("Save settings")) {
                console.log("saving")
                persistUsrDefData(key: gameOptionsKey, data: GameOptionsData(data: gameOptions))
            }
            .buttonStyle(.borderedProminent)

            Button(L10n.string("Reset")) {
                console.log("resetting")
                resetOptions()
            }

            Spacer()

            if includeAutoConfigure, (game?.steamAppID ?? 0) > 0 {
                ProminentButton(
                    L10n.string("Auto configure"),
                    systemImage: "wand.and.sparkles",
                    isLoading: isAutoConfiguring
                ) {
                    Task { await autoConfigure() }
                }
                .disabled(isAutoConfiguring || !isConfiguredMetadataServiceAvailable)
                .help(
                    isConfiguredMetadataServiceAvailable
                        ? L10n.string("Load recommended settings for this game.")
                        : L10n.string("The configured metadata service is unavailable.")
                )
            }
        }
        .padding(.top)

        if includeAutoConfigure, let autoConfigErrorMessage {
            Text(autoConfigErrorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func loadOptions() {
        if let data: GameOptionsData = readUsrDefData(key: gameOptionsKey) {
            gameOptions.set(data: data)
        }
        if isJX3Game {
            OnlineGameMode.applyDefaultRuntimePreferences(to: gameOptions)
        }
    }

    private func resetOptions() {
        gameOptions.set(data: GameOptionsData(data: GameOptions()))
        if isJX3Game {
            OnlineGameMode.applyDefaultRuntimePreferences(to: gameOptions)
        }
    }

    private var selectedBottleURL: URL? {
        OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)
    }

    private func chooseJX3Preset() {
        let panel = NSOpenPanel()
        panel.title = "选择剑网3 config.ini 画质预设"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "ini") ?? .data]
        panel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        importJX3Preset(from: sourceURL)
    }

    private func importRecommendedJX3Preset() {
        guard let sourceURL = BundledOnlineGameResources.resourceURL(
            named: JX3ConfigPresetImporter.recommendedConfigResourceName
        ) else {
            jx3PresetErrorMessage = "App 内未找到内置剑网3推荐画质预设。"
            return
        }
        importJX3Preset(from: sourceURL)
    }

    private func importJX3Preset(from sourceURL: URL) {
        guard let selectedBottleURL else {
            jx3PresetErrorMessage = "请先在设置中选择剑网3使用的 Bottle。"
            return
        }

        isApplyingJX3Preset = true
        jx3PresetMessage = nil
        jx3PresetErrorMessage = nil
        defer { isApplyingJX3Preset = false }

        do {
            _ = try JX3ConfigPresetImporter.importPreset(
                from: sourceURL,
                into: selectedBottleURL
            )
            var details = [
                "已导入 \(sourceURL.lastPathComponent)",
                "SkipVideoCardScoreUpdate=1"
            ]
            do {
                if try OnlineGameInitialConfiguration.applyDLSSFrameGeneration(
                    enabled: false,
                    in: selectedBottleURL
                ) {
                    details.append("DLSS=1")
                } else {
                    details.append("machine_config.ini 尚未生成，DLSS=1 将在初始化时自动补齐")
                }
            } catch {
                details.append("DLSS 将在初始化时自动补齐")
                console.warn("导入剑网3画质预设后暂时无法写入 DLSS=1：\(error.localizedDescription)")
            }

            do {
                if try BundledOnlineGameResources.installNVNGX(into: selectedBottleURL) {
                    details.append("NVNGX 已使用 App 内置版本替换")
                }
            } catch {
                details.append("NVNGX 将在下次启动前自动处理")
                console.warn("导入剑网3画质预设后暂时无法替换 NVNGX：\(error.localizedDescription)")
            }

            OnlineGameInitialConfiguration.startPolling(for: selectedBottleURL)
            jx3PresetMessage = details.joined(separator: "；")
        } catch {
            jx3PresetErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func autoConfigure() async {
        guard let steamAppID = game?.steamAppID, steamAppID > 0 else { return }
        isAutoConfiguring = true
        autoConfigErrorMessage = nil
        defer { isAutoConfiguring = false }

        do {
            let data = try await api.fetchAutoConfig(steamID: String(steamAppID))
            gameOptions.importAutoConfig(data: data)
        } catch {
            autoConfigErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    @State @Previewable var game: Game? = .mock
    @StateObject @Previewable var gameOptions: GameOptions = GameOptions(cxGraphicsBackend: "dxmt")

    GameOptionsView(game: $game)
        .environmentObject(gameOptions)
        .environmentObject(AppGlobals())
}
