//
//  JX3AdditionalSettingsView.swift
//  Arclume
//

import SwiftUI

struct JX3AdditionalSettingsView: View {
    @ObservedObject var gameOptions: GameOptions
    let isRuntimeActive: Bool
    let onSettingsChanged: ((inout GameOptionsData) -> Void) -> Void

    @EnvironmentObject private var appGlobals: AppGlobals
    @State private var isApplyingGPUProfile = false

    private var machineConfigURL: URL? {
        guard let bottle = OnlineGameMode.jx3BottleURL(appGlobals: appGlobals) else { return nil }
        return JX3GameConfiguration.configURL(in: bottle).deletingLastPathComponent()
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("machine_config.ini")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("运行时与图形") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("运行时", value: "Arclume Wine")
                    if OnlineGameMode.supportsD3DMetal4 {
                        DropDown(
                            options: OnlineGameMode.onlineGraphicsBackends,
                            label: "图形后端",
                            value: $gameOptions.cxGraphicsBackend
                        )
                        .onChange(of: gameOptions.cxGraphicsBackend) { _, backend in
                            gameOptions.d3dMtl4Enabled = backend == "d3dmetal4"
                            onSettingsChanged {
                                $0.cxGraphicsBackend = backend
                                $0.d3dMtl4Enabled = backend == "d3dmetal4"
                            }
                        }
                    } else {
                        LabeledContent("图形后端", value: "D3DMetal 4 Beta 3 · 不可用")
                        Text(OnlineGameMode.d3dMetal4RequirementMessage)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("MSync", isOn: $gameOptions.wineMSync)
                }
                .padding(8)
            }
            GroupBox("游戏") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("游戏外画质设置（Beta）", isOn: $gameOptions.externalQualitySettingsEnabled)
                    Toggle("进入游戏后关闭启动器", isOn: $gameOptions.closeLauncherWhenGameStarts)
                        .help("检测到 JX3ClientX64.exe 后，仅关闭 SeasunGame.exe。")
                    Divider()
                    JX3GPUProfileSettingsView(
                        configURL: machineConfigURL,
                        isRuntimeActive: isRuntimeActive,
                        isApplying: $isApplyingGPUProfile
                    )
                }
                .padding(8)
            }
            DisclosureGroup("自定义启动参数") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("启动参数", text: $gameOptions.gameArguments)
                    TextField("环境变量", text: $gameOptions.envVariables)
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 10)
            }
        }
        .frame(width: 460)
        .padding(.vertical)
        .controlSize(.regular)
        .toggleStyle(.switch)
        .onChange(of: gameOptions.externalQualitySettingsEnabled) { _, value in
            onSettingsChanged { $0.externalQualitySettingsEnabled = value }
        }
        .onChange(of: gameOptions.wineMSync) { _, value in
            onSettingsChanged { $0.wineMSync = value }
        }
        .onChange(of: gameOptions.closeLauncherWhenGameStarts) { _, value in
            onSettingsChanged { $0.closeLauncherWhenGameStarts = value }
        }
        .onChange(of: gameOptions.gameArguments) { _, value in
            onSettingsChanged { $0.gameArguments = value }
        }
        .onChange(of: gameOptions.envVariables) { _, value in
            onSettingsChanged { $0.envVariables = value }
        }
    }

    private var runtimeSelection: Binding<String> {
        Binding(
            get: {
                _ = appGlobals.selectedBottle
                return OnlineGameRuntimeKind.selected().rawValue
            },
            set: { rawValue in
                guard OnlineGameMode.isEnabled, !isRuntimeActive, !isApplyingGPUProfile,
                      let runtime = OnlineGameRuntimeKind(rawValue: rawValue),
                      let bottleURL = OnlineGameRuntimeKind.readyBottleURL(
                          for: runtime,
                          appGlobals: appGlobals
                      )
                else {
                    return
                }
                OnlineGameRuntimeKind.activate(
                    runtime,
                    with: bottleURL,
                    appGlobals: appGlobals
                )
            }
        )
    }
}

#Preview {
    JX3AdditionalSettingsView(
        gameOptions: GameOptions(),
        isRuntimeActive: false
    ) { _ in }
    .environmentObject(AppGlobals())
}
