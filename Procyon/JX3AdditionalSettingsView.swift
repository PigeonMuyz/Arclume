//
//  JX3AdditionalSettingsView.swift
//  Procyon
//

import SwiftUI

struct JX3AdditionalSettingsView: View {
    @ObservedObject var gameOptions: GameOptions
    let isRuntimeActive: Bool
    let onSettingsChanged: () -> Void

    @EnvironmentObject private var appGlobals: AppGlobals

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DropDown(
                options: OnlineGameRuntimeKind.launcherRuntimeOptions,
                label: "运行时",
                value: runtimeSelection
            )
            .disabled(isRuntimeActive)

            DropDown(
                options: OnlineGameMode.onlineGraphicsBackends,
                label: "图形后端",
                value: $gameOptions.cxGraphicsBackend
            )
            .onChange(of: gameOptions.cxGraphicsBackend) { _, backend in
                gameOptions.d3dMtl4Enabled = backend == "d3dmetal4"
                onSettingsChanged()
            }

            Divider()

            Toggle(
                "启用游戏外画质设置（Beta）",
                isOn: $gameOptions.externalQualitySettingsEnabled
            )

            Divider()

            Text("兼容性")
                .font(.headline)
            Toggle("MSync", isOn: $gameOptions.wineMSync)
            Toggle(
                "检测到游戏本体后关闭启动器",
                isOn: $gameOptions.closeLauncherWhenGameStarts
            )
            .help("检测到 JX3ClientX64.exe 后，仅关闭 SeasunGame.exe；游戏本体会继续运行。")

            Divider()

            Text("启动参数")
                .font(.headline)
            TextField("启动参数", text: $gameOptions.gameArguments)
            TextField("环境变量", text: $gameOptions.envVariables)
        }
        .frame(width: 390)
        .padding(.vertical)
        .controlSize(.small)
        .toggleStyle(.switch)
        .onChange(of: gameOptions.externalQualitySettingsEnabled) { _, _ in
            onSettingsChanged()
        }
        .onChange(of: gameOptions.wineMSync) { _, _ in onSettingsChanged() }
        .onChange(of: gameOptions.closeLauncherWhenGameStarts) { _, _ in onSettingsChanged() }
        .onChange(of: gameOptions.gameArguments) { _, _ in onSettingsChanged() }
        .onChange(of: gameOptions.envVariables) { _, _ in onSettingsChanged() }
    }

    private var runtimeSelection: Binding<String> {
        Binding(
            get: {
                _ = appGlobals.selectedBottle
                return OnlineGameRuntimeKind.selected().rawValue
            },
            set: { rawValue in
                guard !isRuntimeActive,
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
    ) {}
    .environmentObject(AppGlobals())
}
