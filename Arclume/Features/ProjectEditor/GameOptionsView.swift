//
//  GameOptionsView.swift
//  Arclume
//
//  Created by Italo Mandara on 12/02/2026.
//

import AppKit
import SwiftUI

struct GameOptionsView: View {
    @Binding var game: Game?
    @EnvironmentObject var gameOptions: GameOptions
    @EnvironmentObject private var appGlobals: AppGlobals
    @State private var isAutoConfiguring = false
    @State private var autoConfigErrorMessage: String?
    @State private var isSettingsVisible = false
    @State private var isAdvancedLaunchUnlocked = false

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

    private var gameOptionsKey: String? {
        game.map { namespacedKey("GameOptions", OnlineGameMode.gameOptionsIdentifier(for: $0)) }
    }

    private func savedOption<Value>(
        _ option: ReferenceWritableKeyPath<GameOptions, Value>,
        _ stored: WritableKeyPath<GameOptionsData, Value?>,
        updateRelated: ((Value, inout GameOptionsData) -> Void)? = nil
    ) -> Binding<Value> {
        let key = gameOptionsKey
        return Binding(
            get: { gameOptions[keyPath: option] },
            set: { value in
                guard let key, key == gameOptionsKey else { return }
                gameOptions[keyPath: option] = value
                GameOptionsPersistence.update(key: key) { saved in
                    saved[keyPath: stored] = value
                    updateRelated?(value, &saved)
                }
            }
        )
    }

    private var graphicsBackend: Binding<String> {
        savedOption(\.cxGraphicsBackend, \.cxGraphicsBackend) { backend, saved in
            let enabled = backend == "d3dmetal4"
            gameOptions.d3dMtl4Enabled = enabled
            saved.d3dMtl4Enabled = enabled
        }
    }

    private var metalFX: Binding<Bool> {
        savedOption(\.dxmtMetalFXSpatial, \.dxmtMetalFXSpatial) { enabled, saved in
            guard !enabled else { return }
            gameOptions.dxmtMetalSpatialUpscaleFactor = 1.0
            saved.dxmtMetalSpatialUpscaleFactor = 1.0
        }
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
                .foregroundStyle(.arclumeBrightGray)

            if let game, !game.isNative {
                GameContainerAssignmentView(game: game).padding(.vertical, 10)
            }

            if game != nil {
                if isJX3Game {
                    onlineOptionsForm
                } else {
                    standardOptionsForm
                }
            }
        }
        .padding()
        .background {
            JX3AdvancedLaunchUnlockMonitor(
                isActive: isSettingsVisible && isJX3Game && !isAdvancedLaunchUnlocked
            ) {
                isAdvancedLaunchUnlocked = true
            }
            .id(game?.id)
        }
        .onAppear {
            isSettingsVisible = true
            isAdvancedLaunchUnlocked = false
            loadOptions()
        }
        .onDisappear {
            isSettingsVisible = false
            isAdvancedLaunchUnlocked = false
        }
        .onChange(of: gameOptionsKey) { _, _ in
            isAdvancedLaunchUnlocked = false
            autoConfigErrorMessage = nil
            loadOptions()
        }
    }

    private var onlineOptionsForm: some View {
        Form {
            VStack(alignment: .leading, spacing: 20) {
                Section("剑网3运行选项") {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .trailing, spacing: 12) {
                            DropDown(
                                options: OnlineGameMode.onlineGraphicsBackends,
                                label: "图形方案",
                                value: graphicsBackend
                            )
                            if !OnlineGameMode.supportsD3DMetal4 {
                                Text(OnlineGameMode.d3dMetal4RequirementMessage)
                                    .font(.caption).foregroundStyle(.secondary)
                            }

                            Divider()
                            TextField("启动参数", text: savedOption(\.gameArguments, \.gameArguments))
                            TextField("环境变量", text: savedOption(\.envVariables, \.envVariables))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 12) {
                            Toggle(L10n.string("Metal HUD"), isOn: savedOption(\.mtlHudEnabled, \.mtlHudEnabled))
                            Toggle("MSync", isOn: savedOption(\.wineMSync, \.wineMSync))
                            Toggle(L10n.string("DLSS Frame Generation (Beta)"),
                                   isOn: savedOption(\.dlssFrameGenerationEnabled, \.dlssFrameGenerationEnabled))
                                .help("向客户端声明 DLSS 与帧生成能力（DLSS=2）；关闭时仅声明 DLSS 能力（DLSS=1）。实际开关仍需在游戏画质设置中选择。")
                            Toggle(
                                "检测到游戏本体后关闭启动器",
                                isOn: savedOption(\.closeLauncherWhenGameStarts, \.closeLauncherWhenGameStarts)
                            )
                            .help("检测到 JX3ClientX64.exe 后，仅关闭 SeasunGame.exe。")
                        }
                    }
                }

                if isAdvancedLaunchUnlocked {
                    Toggle("跳过启动器，直接启动游戏", isOn: savedOption(\.jx3SkipLauncher, \.jx3SkipLauncher))
                }

                if gameOptions.cxGraphicsBackend == "dxmt", let game, let prefix = selectedBottleURL {
                    GameShaderSourcePicker(game: game, prefix: prefix)
                }
            }
        }
        .controlSize(.small)
        .formStyle(.columns)
        .toggleStyle(.switch)
    }

    private var standardOptionsForm: some View {
        Group {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("运行与图形") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !game!.isNative {
                            DropDown(options: OnlineGameMode.onlineGraphicsBackends,
                                     label: "图形方案",
                                     value: graphicsBackend,
                                     controlIdentifier: "game-options-graphics-backend")
                            if !OnlineGameMode.supportsD3DMetal4 {
                                Text(OnlineGameMode.d3dMetal4RequirementMessage)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("适用于 Direct3D 转译；Vulkan 游戏（如终末地）仍使用 Vulkan。")
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("MSync", isOn: savedOption(\.wineMSync, \.wineMSync))
                                .accessibilityIdentifier("game-options-msync")
                        }
                        Toggle(L10n.string("Metal HUD"), isOn: savedOption(\.mtlHudEnabled, \.mtlHudEnabled))
                    }
                    .padding(8)
                }

                DisclosureGroup("兼容性与输入设备") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(L10n.string("Advertise AVX"), isOn: savedOption(\.advertiseAVX, \.advertiseAVX))
                        if !game!.isNative {
                            Toggle(L10n.string("Enable SDL"), isOn: savedOption(\.enableSDL, \.enableSDL))
                            Toggle(L10n.string("Disable Hidraw"), isOn: savedOption(\.disableHidraw, \.disableHidraw))
                            Divider()
                            Text(L10n.string("Vulkan options")).font(.subheadline.weight(.medium))
                            Toggle(L10n.string("Enable UE4 Hack"), isOn: savedOption(\.ue4Hack, \.ue4Hack))
                            Toggle(L10n.string("MTL arg. buffers"), isOn: savedOption(\.mvkArgBuff, \.mvkArgBuff))
                        }
                    }
                    .padding(.top, 12)
                }

                DisclosureGroup("自定义启动参数") {
                    VStack(spacing: 12) {
                        TextField(L10n.string("Game arguments"), text: savedOption(\.gameArguments, \.gameArguments))
                        TextField(L10n.string("Env variables"), text: savedOption(\.envVariables, \.envVariables))
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 12)
                }

                if gameOptions.cxGraphicsBackend == "dxmt" {
                    Divider()
                    Section(L10n.string("DXMT Options")) {
                        VStack {
                            Text(L10n.format("Preferred maximum frame rate: %@", preferredMaxFrameRate))
                            Slider(
                                value: savedOption(\.dxmtPreferredMaxFrameRate, \.dxmtPreferredMaxFrameRate),
                                in: 19...240,
                                step: 1.0
                            )
                            .help(L10n.string("Use a value below 20 to let the game choose the frame rate."))
                        }

                        Toggle(L10n.string("MetalFX spatial upscaling"), isOn: metalFX)
                            .help(L10n.string("Enables MetalFX spatial upscaling when the game supports it."))

                        if gameOptions.dxmtMetalFXSpatial {
                            VStack {
                                Text(L10n.format(
                                    "MetalFX spatial upscale factor: %@",
                                    String(gameOptions.dxmtMetalSpatialUpscaleFactor)
                                ))
                                Slider(
                                    value: savedOption(\.dxmtMetalSpatialUpscaleFactor, \.dxmtMetalSpatialUpscaleFactor),
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
                        VStack {
                            Text(L10n.format("Preferred maximum frame rate: %@", d3dMaxFPS))
                            Slider(
                                value: savedOption(\.d3dMaxFPS, \.d3dMaxFPS),
                                in: 19...240,
                                step: 1.0
                            )
                            .help(L10n.string("Use a value below 20 to let the game choose the frame rate."))
                        }
                    }
                }

                if (game?.steamAppID ?? 0) > 0 {
                    autoConfigureAction
                }
                if gameOptions.cxGraphicsBackend == "dxmt", let game, let prefix = selectedBottleURL {
                    GameShaderSourcePicker(game: game, prefix: prefix)
                }
            }
        }
        .frame(width: 480)
        .controlSize(.regular)
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private var autoConfigureAction: some View {
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
        .padding(.top)

        if let autoConfigErrorMessage {
            Text(autoConfigErrorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func loadOptions() {
        guard let gameOptionsKey else { return }
        gameOptions.set(data: GameOptionsPersistence.read(key: gameOptionsKey))
        if game?.isNative == false {
            OnlineGameMode.applyDefaultRuntimePreferences(to: gameOptions)
        }
    }

    private var selectedBottleURL: URL? {
        isJX3Game
            ? OnlineGameMode.jx3BottleURL(appGlobals: appGlobals)
            : OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)
    }

    @MainActor
    private func autoConfigure() async {
        guard let game, let key = gameOptionsKey, game.steamAppID > 0, !isAutoConfiguring else { return }
        isAutoConfiguring = true
        autoConfigErrorMessage = nil
        defer { isAutoConfiguring = false }

        do {
            let data = try await api.fetchAutoConfig(steamID: String(game.steamAppID))
            GameOptionsPersistence.update(key: key) { saved in
                let options = GameOptions()
                options.set(data: saved)
                options.importAutoConfig(data: data)
                if !game.isNative {
                    OnlineGameMode.applyDefaultRuntimePreferences(to: options)
                }
                saved = GameOptionsData(data: options)
            }
            if isSettingsVisible, key == gameOptionsKey { loadOptions() }
        } catch {
            if isSettingsVisible, key == gameOptionsKey { autoConfigErrorMessage = error.localizedDescription }
        }
    }
}

nonisolated struct JX3AdvancedLaunchUnlockSequence {
    private var recent: [String] = []
    private static let sequences = [
        ["↑", "↑", "↓", "↓", "←", "←", "→", "→"],
        ["w", "w", "s", "s", "a", "a", "d", "d"]
    ]

    mutating func accept(_ key: String) -> Bool {
        recent.append(key.lowercased())
        if recent.count > 8 { recent.removeFirst(recent.count - 8) }
        guard Self.sequences.contains(recent) else { return false }
        recent.removeAll(keepingCapacity: true)
        return true
    }
}

private struct JX3AdvancedLaunchUnlockMonitor: NSViewRepresentable {
    let isActive: Bool
    let onUnlock: () -> Void

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onUnlock = onUnlock
        view.isActive = isActive
    }

    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.stop() }

    final class KeyView: NSView {
        var onUnlock: (() -> Void)?
        var isActive = false {
            didSet {
                if isActive { start() } else { stop() }
            }
        }
        private var monitor: Any?
        private var sequence = JX3AdvancedLaunchUnlockSequence()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stop() } else if isActive { start() }
        }

        private func start() {
            guard monitor == nil, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.isActive, let window = self.window,
                          event.window === window, window.isKeyWindow,
                          !self.isHiddenOrHasHiddenAncestor, !event.isARepeat,
                          event.modifierFlags.intersection([.command, .control, .option]).isEmpty
                    else { return }
                    let key: String
                    switch event.keyCode {
                    case 126: key = "↑"
                    case 125: key = "↓"
                    case 123: key = "←"
                    case 124: key = "→"
                    default: key = event.charactersIgnoringModifiers ?? ""
                    }
                    if self.sequence.accept(key) { self.onUnlock?() }
                }
                // Observe without consuming text entry, arrows, or shortcuts.
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            sequence = JX3AdvancedLaunchUnlockSequence()
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
