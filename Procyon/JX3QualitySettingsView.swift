//
//  JX3QualitySettingsView.swift
//  Procyon
//

import Foundation
import SwiftUI

private enum JX3PostEffect: Hashable {
    case ambientOcclusion
    case fullScreenSoftLight
    case depthOfField
    case screenDistortion
    case lensLight
    case waterReflection
    case fullScreenSharpen
    case hair
    case volumetricCloud
    case reflectionEnhancement
    case firework
    case screenSpaceReflection
}

private enum JX3PostEffectPolicy {
    case all
    case onlyFullScreenSoftLight
    case withoutReflectionEnhancement

    func allows(_ effect: JX3PostEffect) -> Bool {
        switch self {
        case .all:
            true
        case .onlyFullScreenSoftLight:
            effect == .fullScreenSoftLight
        case .withoutReflectionEnhancement:
            effect != .reflectionEnhancement
        }
    }
}

private enum JX3QualitySettingsError: LocalizedError, Sendable {
    case configNotFound
    case writeNotConfirmed

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            "未找到当前 Games 容器中的 config.ini，画质设置未写入。"
        case .writeNotConfirmed:
            "无法确认 config.ini 已写入，画质设置未标记为成功。"
        }
    }
}

private enum JX3ModelEdition: String, Sendable {
    case handDrawn
    case flagship

    var title: String {
        switch self {
        case .handDrawn:
            "手绘版模型"
        case .flagship:
            "旗舰版模型"
        }
    }

    var symbolName: String {
        switch self {
        case .handDrawn:
            "pencil"
        case .flagship:
            "sparkles"
        }
    }

}

private struct JX3OfficialQualityPreset: Identifiable {
    let id: String
    let title: String
    let resourceName: String

    var modelEdition: JX3ModelEdition {
        switch id {
        case "zuijian", "jianyue", "junheng":
            .handDrawn
        default:
            .flagship
        }
    }

    var modelEditionTitle: String {
        modelEdition.title
    }

    var verticalTitle: String {
        title.map { String($0) }.joined(separator: "\n")
    }

    var modelSymbolName: String {
        modelEdition.symbolName
    }

    var usesHandDrawnModels: Bool {
        modelEdition == .handDrawn
    }

    static let all: [JX3OfficialQualityPreset] = [
        JX3OfficialQualityPreset(
            id: "zuijian",
            title: "最简",
            resourceName: "config_bd_1_zuijian.ini"
        ),
        JX3OfficialQualityPreset(
            id: "jianyue",
            title: "简约",
            resourceName: "config_bd_2_jianyue.ini"
        ),
        JX3OfficialQualityPreset(
            id: "junheng",
            title: "标准",
            resourceName: "config_bd_3_junheng.ini"
        ),
        JX3OfficialQualityPreset(
            id: "dianying",
            title: "电影",
            resourceName: "config_bd_6_dianying.ini"
        ),
        JX3OfficialQualityPreset(
            id: "jizhi",
            title: "极致",
            resourceName: "config_bd_7_jizhi.ini"
        ),
        JX3OfficialQualityPreset(
            id: "tansuo",
            title: "探索",
            resourceName: "config_bd_7_tansuo.ini"
        )
    ]
}

private enum JX3QualitySection: CaseIterable, Hashable, Identifiable {
    case performance
    case effects
    case rendering
    case postProcessing
    case display

    var id: Self { self }

    var title: String {
        switch self {
        case .performance:
            "效率"
        case .effects:
            "特效"
        case .rendering:
            "渲染"
        case .postProcessing:
            "后期"
        case .display:
            "画面"
        }
    }
}

nonisolated private struct JX3INIKey: Hashable, Sendable {
    let section: String
    let key: String
}

nonisolated private struct JX3INIReader: Sendable {
    private let values: [JX3INIKey: String]

    init(url: URL?) {
        guard let url,
              let data = try? Data(contentsOf: url)
        else {
            values = [:]
            return
        }

        var parsed: [JX3INIKey: String] = [:]
        var section = ""
        let contents = String(decoding: data, as: UTF8.self)
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            guard !line.isEmpty,
                  !line.hasPrefix(";") && !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=")
            else {
                continue
            }

            let key = String(line[..<separator])
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            parsed[JX3INIKey(section: section, key: key)] = value
        }
        values = parsed
    }

    func string(_ section: String, _ key: String) -> String? {
        values[JX3INIKey(section: section, key: key)]
    }

    func int(_ section: String, _ key: String, default fallback: Int) -> Int {
        Int(string(section, key) ?? "") ?? fallback
    }

    func double(_ section: String, _ key: String, default fallback: Double) -> Double {
        Double(string(section, key) ?? "") ?? fallback
    }

    func bool(_ section: String, _ key: String, default fallback: Bool) -> Bool {
        guard let value = string(section, key)?.lowercased() else { return fallback }
        return value == "1" || value == "true"
    }
}

nonisolated private enum JX3Antialiasing: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case nis
    case smaa
    case dlss
    case taa
    case fsr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            "关闭选项"
        case .nis:
            "NIS图像压缩"
        case .smaa:
            "SMAA抗锯齿"
        case .dlss:
            "DLSS抗锯齿"
        case .taa:
            "TAA抗锯齿"
        case .fsr:
            "FSR锐画"
        }
    }

    var showsUpscalingControls: Bool {
        self == .dlss || self == .fsr
    }
}

nonisolated private enum JX3EffectCullDistance: String, CaseIterable, Identifiable, Sendable {
    case near
    case far
    case veryFar
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .near:
            "近"
        case .far:
            "远"
        case .veryFar:
            "超远"
        case .custom:
            "自定义"
        }
    }

    var distances: (first: Int, second: Int, third: Int)? {
        switch self {
        case .near:
            (3000, 4000, 8000)
        case .far:
            (5000, 6000, 8000)
        case .veryFar:
            (4000, 5000, 8000)
        case .custom:
            nil
        }
    }

    static func resolve(first: Int, second: Int, third: Int) -> JX3EffectCullDistance {
        allCases.first { preset in
            guard let distances = preset.distances else { return false }
            return distances.first == first
                && distances.second == second
                && distances.third == third
        } ?? .custom
    }
}

nonisolated private enum JX3QualityConfigAntialiasing {
    static func resolve(from ini: JX3INIReader) -> JX3Antialiasing {
        if ini.int("KG3DENGINE", "AAOPTION_DLSSOption", default: 0) > 0 {
            return .dlss
        }
        if ini.bool("KG3DENGINE", "AAOPTION_EnableSMAA", default: false)
            || ini.bool("KG3DENGINE", "bEnableRC_SMAA", default: false) {
            return .smaa
        }
        if ini.bool("KG3DENGINE", "AAOPTION_EnableTXAA", default: false) {
            return .taa
        }
        if ini.bool("KG3DENGINE", "EnableNIS", default: false) {
            return .nis
        }
        if ini.bool("KG3DENGINE", "EnableFSR2", default: false)
            || ini.bool("KG3DENGINE", "EnableFSR", default: false) {
            return .fsr
        }
        return .disabled
    }
}

nonisolated private struct JX3QualityConfigValues: Equatable, Sendable {
    var frameRateLimit = 67
    var playerModelLimit = 40
    var npcModelLimit = 50
    var clientSFXLimit = 1000
    var screenSizeLimitedRate = 1.0

    var enableFabric = true
    var enableSkillOptimization = true
    var enableLensLight = true
    var enableCombi = false
    var showOutline = true
    var campUniform = false

    var dungeonOptimization = true
    var ownEffectLevel = 2
    var otherEffectLevel = 3
    var ownEffectIntensity = 1.0
    var otherEffectIntensity = 1.0
    var effectCullDistance: JX3EffectCullDistance = .custom
    var sfxLodDist1 = 4_000
    var sfxLodDist2 = 5_000
    var sfxLodDist3 = 8_000

    var foliageDensity = 50
    var speedTreeDensity = 50
    var shadowType = 0
    var waterEffectLevel = 2
    var shadowQuantity = 90
    var pointLightLimitEnabled = true
    var farDisplayDistance = 50_000
    var engineGraphicsLevel = 3
    var terrainBakeScaleRate = 2
    var speedTreeLeafScale = 100.0

    var ambientOcclusion = true
    var screenDistortion = true
    var fullScreenSoftLight = true
    var hair = true
    var firework = false
    var depthOfField = true
    var waterReflection = true
    var volumetricCloud = true
    var screenSpaceReflection = true
    var fullScreenSharpen = false
    var reflectionEnhancement = false

    var antialiasing: JX3Antialiasing = .dlss
    var upscaleMode = 0
    var sharpness = 0.0

    init(configURL: URL? = nil) {
        let ini = JX3INIReader(url: configURL)

        frameRateLimit = ini.int("ENGINEOPTION", "MaxFPS", default: frameRateLimit)
        playerModelLimit = min(
            1_000,
            max(0, ini.int("ENGINEOPTION", "MDLRenderLimit", default: playerModelLimit))
        )
        npcModelLimit = min(
            1_000,
            max(0, ini.int("ENGINEOPTION", "MDLRenderNpcLimit", default: npcModelLimit))
        )
        let engineSFXLimit = ini.int("KG3DENGINE", "ClientSFXLimit", default: -1)
        clientSFXLimit = engineSFXLimit >= 0
            ? engineSFXLimit
            : ini.int("ENGINEOPTION", "ClientSFXLimit", default: clientSFXLimit)
        let configuredScreenSizeRate = ini.double(
            "ENGINEOPTION",
            "ScreenSizeLimitedRate",
            default: screenSizeLimitedRate
        )
        screenSizeLimitedRate = min(
            2,
            max(0.5, (configuredScreenSizeRate * 100).rounded() / 100)
        )

        enableFabric = ini.bool("UIVideoSetting", "Fabric", default: enableFabric)
        enableSkillOptimization = ini.bool(
            "UIVideoSetting",
            "OptimizeSkill",
            default: enableSkillOptimization
        )
        enableLensLight = ini.bool(
            "KG3DENGINE",
            "bEnableRC_SunLensflare",
            default: ini.bool("KG3DENGINE", "bEnableLensLightGlobal", default: enableLensLight)
        )
        enableCombi = ini.bool("UIVideoSetting", "Combi", default: enableCombi)
        showOutline = ini.bool("UIVideoSetting", "ShowOutline", default: showOutline)
        campUniform = ini.bool("UIVideoSetting", "CampUniform", default: campUniform)

        dungeonOptimization = ini.bool(
            "UIVideoSetting",
            "DungeonSceneSetting",
            default: dungeonOptimization
        )
        ownEffectLevel = ini.int("UIVideoSetting", "MyEffect", default: ownEffectLevel)
        otherEffectLevel = ini.int("UIVideoSetting", "OtherEffect", default: otherEffectLevel)
        ownEffectIntensity = ini.double(
            "ENGINEOPTION",
            "MyEffectAlpha",
            default: ownEffectIntensity
        )
        otherEffectIntensity = ini.double(
            "ENGINEOPTION",
            "OtherEffectAlpha",
            default: otherEffectIntensity
        )
        sfxLodDist1 = ini.int("ENGINEOPTION", "nSfxLodDist1", default: sfxLodDist1)
        sfxLodDist2 = ini.int("ENGINEOPTION", "nSfxLodDist2", default: sfxLodDist2)
        sfxLodDist3 = ini.int("ENGINEOPTION", "nSfxLodDist3", default: sfxLodDist3)
        effectCullDistance = JX3EffectCullDistance.resolve(
            first: sfxLodDist1,
            second: sfxLodDist2,
            third: sfxLodDist3
        )

        foliageDensity = ini.int("KG3DENGINE", "nFoliageDensity", default: foliageDensity)
        speedTreeDensity = ini.int("KG3DENGINE", "nSpeedTreeDensity", default: speedTreeDensity)
        shadowType = ini.int("KG3DENGINE", "nShadowType", default: shadowType)
        waterEffectLevel = ini.int("KG3DENGINE", "nWaterEffectLevel", default: waterEffectLevel)
        shadowQuantity = ini.int(
            "KG3DENGINE",
            "nRenderPointLightLimitCount",
            default: shadowQuantity
        )
        pointLightLimitEnabled = ini.bool(
            "KG3DENGINE",
            "bRenderPointLightLimit",
            default: pointLightLimitEnabled
        )
        farDisplayDistance = Int(ini.double(
            "KG3DENGINE",
            "fCameraDistanceHD",
            default: Double(farDisplayDistance)
        ).rounded())
        engineGraphicsLevel = ini.int(
            "ENGINEOPTION",
            "nEngineGraphicsLevel",
            default: engineGraphicsLevel
        )
        terrainBakeScaleRate = ini.int(
            "KG3DENGINE",
            "nTerrainBakeScaleRate",
            default: terrainBakeScaleRate
        )
        speedTreeLeafScale = ini.double(
            "KG3DENGINE",
            "nSpeedTreeLeafScale",
            default: speedTreeLeafScale
        )

        ambientOcclusion = ini.bool(
            "KG3DENGINE",
            "bEnableRC_AmbientOcclusion",
            default: ambientOcclusion
        )
        screenDistortion = ini.bool(
            "KG3DENGINE",
            "bEnableRC_ShockWave",
            default: screenDistortion
        )
        fullScreenSoftLight = ini.bool(
            "KG3DENGINE",
            "bEnableRC_Bloom",
            default: fullScreenSoftLight
        )
        hair = ini.bool("KG3DENGINE", "EnableFur", default: hair)
        firework = ini.bool("KG3DENGINE", "bDiamondFire", default: firework)
        depthOfField = ini.bool(
            "KG3DENGINE",
            "bEnableRC_Depth",
            default: depthOfField
        )
        waterReflection = ini.bool(
            "KG3DENGINE",
            "WaterReflection",
            default: ini.bool("KG3DENGINE", "bEnableSSPR", default: waterReflection)
        )
        volumetricCloud = ini.bool(
            "KG3DENGINE",
            "bEnableRC_StingRayVolumetircCloud",
            default: volumetricCloud
        )
        screenSpaceReflection = ini.bool(
            "KG3DENGINE",
            "bEnable_SSR",
            default: ini.bool("KG3DENGINE", "bEnableRC_SSR", default: screenSpaceReflection)
        )
        fullScreenSharpen = ini.bool(
            "KG3DENGINE",
            "bEnableCASSharper",
            default: fullScreenSharpen
        )
        reflectionEnhancement = ini.bool(
            "KG3DENGINE",
            "bOpenSunLightShadowSharpen",
            default: reflectionEnhancement
        )

        antialiasing = JX3QualityConfigAntialiasing.resolve(from: ini)
        upscaleMode = ini.int("KG3DENGINE", "FSR2Option", default: upscaleMode)
        sharpness = JX3QualityConfigValues.sharpness(from: ini, antialiasing: antialiasing)
    }

    var updates: [OnlineGameInitialConfiguration.INIUpdate] {
        let effectDistances = effectCullDistance.distances
        let selectedDistances = effectDistances ?? (sfxLodDist1, sfxLodDist2, sfxLodDist3)

        return [
            update("ENGINEOPTION", "MaxFPS", intString(frameRateLimit)),
            update("ENGINEOPTION", "MDLRenderLimit", intString(playerModelLimit)),
            update("ENGINEOPTION", "MDLRenderNpcLimit", intString(npcModelLimit)),
            update("ENGINEOPTION", "ClientSFXLimit", intString(clientSFXLimit)),
            update("KG3DENGINE", "ClientSFXLimit", intString(clientSFXLimit)),
            update("ENGINEOPTION", "ScreenSizeLimitedRate", decimalString(screenSizeLimitedRate)),

            update("UIVideoSetting", "Fabric", boolString(enableFabric)),
            update("UIVideoSetting", "OptimizeSkill", boolString(enableSkillOptimization)),
            update("UIVideoSetting", "Combi", boolString(enableCombi)),
            update("UIVideoSetting", "ShowOutline", boolString(showOutline)),
            update("UIVideoSetting", "CampUniform", boolString(campUniform)),
            update("KG3DENGINE", "bEnableRC_SunLensflare", boolString(enableLensLight)),
            update("KG3DENGINE", "bEnableLensLightGlobal", boolString(enableLensLight)),

            update("UIVideoSetting", "DungeonSceneSetting", boolString(dungeonOptimization)),
            update("UIVideoSetting", "MyEffect", intString(ownEffectLevel)),
            update("UIVideoSetting", "OtherEffect", intString(otherEffectLevel)),
            update("ENGINEOPTION", "MyEffectAlpha", decimalString(ownEffectIntensity)),
            update("ENGINEOPTION", "MyEffectLight", decimalString(ownEffectIntensity)),
            update("ENGINEOPTION", "OtherEffectAlpha", decimalString(otherEffectIntensity)),
            update("ENGINEOPTION", "OtherEffectLight", decimalString(otherEffectIntensity)),
            update("ENGINEOPTION", "nSfxLodDist1", intString(selectedDistances.0)),
            update("ENGINEOPTION", "nSfxLodDist2", intString(selectedDistances.1)),
            update("ENGINEOPTION", "nSfxLodDist3", intString(selectedDistances.2)),

            update("KG3DENGINE", "nFoliageDensity", intString(foliageDensity)),
            update("KG3DENGINE", "nSpeedTreeDensity", intString(speedTreeDensity)),
            update("KG3DENGINE", "nShadowType", intString(shadowType)),
            update("KG3DENGINE", "nWaterEffectLevel", intString(waterEffectLevel)),
            update("KG3DENGINE", "nRenderPointLightLimitCount", intString(shadowQuantity)),
            update("KG3DENGINE", "bRenderPointLightLimit", boolString(pointLightLimitEnabled)),
            update("KG3DENGINE", "fCameraDistanceHD", intString(farDisplayDistance)),
            update("ENGINEOPTION", "nEngineGraphicsLevel", intString(engineGraphicsLevel)),
            update("KG3DENGINE", "nTerrainBakeScaleRate", intString(terrainBakeScaleRate)),
            update("KG3DENGINE", "nSpeedTreeLeafScale", decimalString(speedTreeLeafScale)),

            update("KG3DENGINE", "bEnableRC_AmbientOcclusion", boolString(ambientOcclusion)),
            update("KG3DENGINE", "bEnableRC_ShockWave", boolString(screenDistortion)),
            update("KG3DENGINE", "bEnableRC_Bloom", boolString(fullScreenSoftLight)),
            update("KG3DENGINE", "EnableFur", boolString(hair)),
            update("KG3DENGINE", "bDiamondFire", boolString(firework)),
            update("KG3DENGINE", "bEnableRC_Depth", boolString(depthOfField)),
            update("KG3DENGINE", "WaterReflection", boolString(waterReflection)),
            update("KG3DENGINE", "bEnableSSPR", boolString(waterReflection)),
            update(
                "KG3DENGINE",
                "bEnableRC_StingRayVolumetircCloud",
                boolString(volumetricCloud)
            ),
            update("KG3DENGINE", "bEnableCASSharper", boolString(fullScreenSharpen)),
            update(
                "KG3DENGINE",
                "bOpenSunLightShadowSharpen",
                boolString(reflectionEnhancement)
            ),
            update("KG3DENGINE", "bEnableRC_SSR", boolString(screenSpaceReflection)),
            update("KG3DENGINE", "bEnable_SSR", boolString(screenSpaceReflection)),

            update("KG3DENGINE", "AAOPTION_EnableTXAA", boolString(antialiasing == .taa)),
            update("KG3DENGINE", "AAOPTION_EnableSMAA", boolString(antialiasing == .smaa)),
            update("KG3DENGINE", "bEnableRC_SMAA", boolString(antialiasing == .smaa)),
            update("KG3DENGINE", "AAOPTION_DLSSOption", intString(antialiasing == .dlss ? 1 : 0)),
            update("KG3DENGINE", "EnableNIS", boolString(antialiasing == .nis)),
            update("KG3DENGINE", "EnableFSR", boolString(antialiasing == .fsr)),
            update("KG3DENGINE", "EnableFSR2", boolString(antialiasing == .fsr)),
            update("KG3DENGINE", "FSR2Option", intString(upscaleMode)),
            update("KG3DENGINE", "FSR3UpscaleOption", intString(upscaleMode)),
            update("KG3DENGINE", "AAOPTION_DLSSParam", decimalString(sharpness)),
            update("KG3DENGINE", "FSR2Sharpnees", decimalString(sharpness)),
            update("KG3DENGINE", "FSR3Sharpness", decimalString(sharpness)),
            update("KG3DENGINE", "NISSharpness", decimalString(sharpness))
        ]
    }

    private static func sharpness(
        from ini: JX3INIReader,
        antialiasing: JX3Antialiasing
    ) -> Double {
        switch antialiasing {
        case .nis:
            return ini.double("KG3DENGINE", "NISSharpness", default: 0)
        case .fsr:
            return ini.double("KG3DENGINE", "FSR2Sharpnees", default: 0)
        case .disabled, .smaa, .dlss, .taa:
            return ini.double("KG3DENGINE", "AAOPTION_DLSSParam", default: 0)
        }
    }

    private func update(
        _ section: String,
        _ key: String,
        _ value: String
    ) -> OnlineGameInitialConfiguration.INIUpdate {
        OnlineGameInitialConfiguration.INIUpdate(
            section: section,
            key: key,
            value: value
        )
    }

    private func intString(_ value: Int) -> String {
        String(value)
    }

    private func boolString(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private func decimalString(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

struct JX3QualitySettingsView: View {
    let bottleURL: URL?
    @State private var settings = JX3QualityConfigValues()
    @State private var modelEdition: JX3ModelEdition = .flagship
    @State private var selectedSection: JX3QualitySection = .performance
    @State private var isApplying = false
    @State private var isLoadingSettings = true
    @State private var autoApplyTask: Task<Void, Never>?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var postEffectPolicy: JX3PostEffectPolicy {
        switch settings.engineGraphicsLevel {
        case 1, 2:
            .onlyFullScreenSoftLight
        case 4:
            .withoutReflectionEnhancement
        default:
            .all
        }
    }

    private var usesHandDrawnModels: Bool {
        modelEdition == .handDrawn
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                officialPresetCard

                if isLoadingSettings {
                    settingsLoadingState
                } else {
                    sectionPicker
                    qualitySection(selectedSection)
                        .disabled(isApplying || bottleURL == nil)
                }

                if bottleURL == nil {
                    Text("请先选择剑网3使用的 Bottle。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if isApplying {
                    ProgressView("正在应用…")
                        .controlSize(.small)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 12)
        }
        .frame(width: 620, alignment: .topLeading)
        .frame(height: 650, alignment: .topLeading)
        .controlSize(.small)
        .task {
            await reloadSettings()
        }
        .onChange(of: settings) { _, _ in
            scheduleAutoApply()
        }
        .onDisappear {
            autoApplyTask?.cancel()
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 5) {
            ForEach(JX3QualitySection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                selectedSection == section
                                    ? .white
                                    : .white.opacity(0.58)
                            )
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        selectedSection == section
                            ? .procyonSecondary.opacity(0.22)
                            : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(5)
        .background(
            .black.opacity(0.13),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var settingsLoadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取画质参数…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            .black.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func qualitySection(_ section: JX3QualitySection) -> some View {
        switch section {
        case .performance:
            settingsCard("效率选项", systemImage: "gauge.with.dots.needle.67") {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 8
                ) {
                    qualityToggle("布料效果", isOn: $settings.enableFabric)
                    qualityToggle("技能性能", isOn: $settings.enableSkillOptimization)
                    qualityToggle("镜头光", isOn: $settings.enableLensLight)
                    qualityToggle(
                        "虚拟几何",
                        isOn: .constant(false),
                        enabled: false
                    )
                    qualityToggle("合并绘制", isOn: $settings.enableCombi)
                    qualityToggle("屏蔽勾边", isOn: $settings.showOutline)
                    qualityToggle("阵营同模", isOn: $settings.campUniform)
                }

                Divider().overlay(.white.opacity(0.08))

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    intSliderRow("帧速上限", value: $settings.frameRateLimit, range: 30...67)
                    intSliderRow("同屏玩家数", value: $settings.playerModelLimit, range: 0...1_000)
                    intSliderRow("同屏 NPC 数", value: $settings.npcModelLimit, range: 0...1_000)
                    intSliderRow("同屏特效数", value: $settings.clientSFXLimit, range: 0...1_000)
                    sliderRow(
                        "画面精度",
                        value: screenSizeRateBinding,
                        range: 0.5...2,
                        step: 0.01,
                        formatter: { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }
                    )
                }
            }

        case .effects:
            settingsCard("特效选项", systemImage: "sparkles") {
                HStack(spacing: 12) {
                    qualityToggle("秘境优化策略", isOn: $settings.dungeonOptimization)
                    Spacer(minLength: 8)
                    Button("放置技能屏蔽") {}
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.35))
                        .disabled(true)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 8
                ) {
                    pickerRow("自身特效", selection: $settings.ownEffectLevel) {
                        effectLevelOptions
                    }
                    pickerRow("其他玩家", selection: $settings.otherEffectLevel) {
                        effectLevelOptions
                    }
                    pickerRow("特效裁剪距离", selection: effectCullDistanceBinding) {
                        ForEach(JX3EffectCullDistance.allCases) { distance in
                            Text(distance.title).tag(distance)
                        }
                    }
                }
            }

        case .rendering:
            settingsCard("渲染选项", systemImage: "cube.transparent") {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 8
                ) {
                    pickerRow("植被密度", selection: foliageDensityBinding) {
                        Text("低").tag(10)
                        Text("高").tag(50)
                        Text("极高").tag(100)
                    }
                    pickerRow("阴影质量", selection: $settings.shadowType) {
                        Text("无").tag(0)
                        Text("中").tag(1)
                        Text("高").tag(2)
                        Text("极高").tag(3)
                        Text("低").tag(7)
                    }
                    pickerRow("水面精度", selection: $settings.waterEffectLevel) {
                        Text("极高").tag(0)
                        Text("高").tag(1)
                        Text("中").tag(2)
                        Text("低").tag(3)
                    }
                    pickerRow("阴影数量", selection: $settings.shadowQuantity) {
                        Text("低").tag(0)
                        Text("中").tag(40)
                        Text("超高").tag(90)
                        Text("极高").tag(100)
                    }
                    pickerRow("远景显示", selection: farDisplayBinding) {
                        Text("低").tag(20_000)
                        Text("中").tag(50_000)
                        Text("高").tag(100_000)
                        Text("极高").tag(800_000)
                    }
                    pickerRow("物件细节", selection: $settings.engineGraphicsLevel) {
                        ForEach(1...8, id: \.self) { level in
                            Text(engineGraphicsLevelTitle(level)).tag(level)
                        }
                    }
                    pickerRow("地形烘焙", selection: $settings.terrainBakeScaleRate) {
                        Text("高").tag(1)
                        Text("中").tag(2)
                        Text("低").tag(4)
                    }
                    sliderRow(
                        "树叶缩放",
                        value: $settings.speedTreeLeafScale,
                        range: 0...100,
                        step: 1,
                        formatter: integerString
                    )
                }
            }

        case .postProcessing:
            settingsCard("后期选项", systemImage: "wand.and.stars") {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 8
                ) {
                    qualityToggle(
                        "环境光屏蔽",
                        isOn: $settings.ambientOcclusion,
                        enabled: postEffectPolicy.allows(.ambientOcclusion)
                    )
                    qualityToggle(
                        "全屏柔光",
                        isOn: $settings.fullScreenSoftLight,
                        enabled: postEffectPolicy.allows(.fullScreenSoftLight)
                    )
                    qualityToggle(
                        "景深效果",
                        isOn: $settings.depthOfField,
                        enabled: postEffectPolicy.allows(.depthOfField)
                    )
                    qualityToggle(
                        "屏幕扭曲",
                        isOn: $settings.screenDistortion,
                        enabled: postEffectPolicy.allows(.screenDistortion)
                    )
                    qualityToggle(
                        "镜头光斑",
                        isOn: $settings.enableLensLight,
                        enabled: postEffectPolicy.allows(.lensLight)
                    )
                    qualityToggle(
                        "水体反射",
                        isOn: $settings.waterReflection,
                        enabled: postEffectPolicy.allows(.waterReflection)
                    )
                    qualityToggle(
                        "全屏锐化",
                        isOn: $settings.fullScreenSharpen,
                        enabled: postEffectPolicy.allows(.fullScreenSharpen)
                    )
                    qualityToggle(
                        "毛发效果",
                        isOn: $settings.hair,
                        enabled: postEffectPolicy.allows(.hair)
                    )
                    qualityToggle(
                        "体积云",
                        isOn: $settings.volumetricCloud,
                        enabled: postEffectPolicy.allows(.volumetricCloud)
                    )
                    qualityToggle(
                        "倒影增强",
                        isOn: $settings.reflectionEnhancement,
                        enabled: postEffectPolicy.allows(.reflectionEnhancement)
                    )
                    qualityToggle(
                        "火彩效果",
                        isOn: $settings.firework,
                        enabled: postEffectPolicy.allows(.firework)
                    )
                    qualityToggle(
                        "屏幕空间反射",
                        isOn: $settings.screenSpaceReflection,
                        enabled: postEffectPolicy.allows(.screenSpaceReflection)
                    )
                }
            }

        case .display:
            settingsCard("画面选项", systemImage: "display") {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(JX3Antialiasing.allCases) { option in
                        antialiasingButton(option)
                    }
                }

                if settings.antialiasing.showsUpscalingControls {
                    Divider().overlay(.white.opacity(0.08))

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        pickerRow("档位", selection: $settings.upscaleMode) {
                            Text("超性能").tag(0)
                            Text("性能").tag(1)
                            Text("均衡").tag(2)
                            Text("质量").tag(3)
                        }
                        sliderRow(
                            "锐度",
                            value: $settings.sharpness,
                            range: 0...1,
                            step: 0.01,
                            formatter: { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }
                        )
                    }
                }
            }
        }
    }

    private var officialPresetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("官方预设", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    Label("手绘版模型", systemImage: "pencil")
                        .foregroundStyle(.white.opacity(0.56))
                    Label("旗舰版模型", systemImage: "sparkles")
                        .foregroundStyle(.procyonSecondary)
                }
                .font(.caption.weight(.medium))
                Button {
                    restoreProcyonPreset()
                } label: {
                    Label("恢复作者推荐预设", systemImage: "arrow.counterclockwise")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            .white.opacity(0.06),
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.procyonSecondary)
            }

            officialPresetButtons
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .procyonAccent.mix(with: .black, by: 0.66).opacity(0.78),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .disabled(isApplying || isLoadingSettings || bottleURL == nil)
    }

    private func settingsCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .procyonAccent.mix(with: .black, by: 0.66).opacity(0.78),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func qualityToggle(
        _ title: String,
        isOn: Binding<Bool>,
        enabled: Bool = true
    ) -> some View {
        if enabled {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "square")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 14, height: 14)
                Text(title)
            }
            .foregroundStyle(.white.opacity(0.32))
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，不可用")
            .accessibilityAddTraits(.isStaticText)
        }
    }

    private func antialiasingButton(_ option: JX3Antialiasing) -> some View {
        let isAvailable = !usesHandDrawnModels || option == .disabled || option == .smaa
        let isSelected = settings.antialiasing == option && isAvailable

        return Button {
            settings.antialiasing = option
        } label: {
            Label(
                option.title,
                systemImage: isSelected
                    ? "circle.inset.filled"
                    : "circle"
            )
            .foregroundStyle(
                isSelected
                    ? .procyonSecondary
                    : .white.opacity(isAvailable ? 0.82 : 0.28)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? .procyonSecondary.opacity(0.16)
                    : .white.opacity(isAvailable ? 0.035 : 0.018),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(
            isAvailable
                ? option.title
                : "\(option.title)，手绘版模型不可用"
        )
    }

    private func pickerRow<Selection: Hashable, Options: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)

            Spacer(minLength: 4)

            Picker("", selection: selection) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 118, alignment: .trailing)
            .tint(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var effectLevelOptions: some View {
        Group {
            Text("高").tag(0)
            Text("较高").tag(1)
            Text("中").tag(2)
            Text("低").tag(3)
        }
    }

    private var effectCullDistanceBinding: Binding<JX3EffectCullDistance> {
        Binding(
            get: { settings.effectCullDistance },
            set: { newValue in
                settings.effectCullDistance = newValue
                if let distances = newValue.distances {
                    settings.sfxLodDist1 = distances.first
                    settings.sfxLodDist2 = distances.second
                    settings.sfxLodDist3 = distances.third
                }
            }
        )
    }

    private var foliageDensityBinding: Binding<Int> {
        Binding(
            get: { settings.foliageDensity },
            set: { newValue in
                settings.foliageDensity = newValue
                switch newValue {
                case 10:
                    settings.speedTreeDensity = 15
                case 50:
                    if settings.speedTreeDensity < 15 || settings.speedTreeDensity > 100 {
                        settings.speedTreeDensity = 80
                    }
                case 100:
                    settings.speedTreeDensity = 100
                default:
                    break
                }
            }
        )
    }

    private var farDisplayBinding: Binding<Int> {
        Binding(
            get: { settings.farDisplayDistance },
            set: { settings.farDisplayDistance = $0 }
        )
    }

    private var screenSizeRateBinding: Binding<Double> {
        Binding(
            get: { settings.screenSizeLimitedRate },
            set: { newValue in
                let roundedValue = (newValue * 100).rounded() / 100
                settings.screenSizeLimitedRate = min(2, max(0.5, roundedValue))
            }
        )
    }

    private func intSliderRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        sliderRow(
            title,
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ),
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: 1,
            formatter: integerString
        )
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatter: @escaping (Double) -> String
    ) -> some View {
        JX3DraftSliderRow(
            title: title,
            value: value,
            range: range,
            step: step,
            formatter: formatter
        )
    }

    private var officialPresetButtons: some View {
        HStack(spacing: 10) {
            ForEach(JX3OfficialQualityPreset.all) { preset in
                Button {
                    applyOfficialPreset(preset)
                } label: {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text(preset.verticalTitle)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineSpacing(1)
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer(minLength: 6)
                        Image(systemName: preset.modelSymbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                preset.usesHandDrawnModels
                                    ? .white.opacity(0.52)
                                    : .procyonSecondary
                            )
                            .help(preset.modelEditionTitle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(
                        .white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.07), lineWidth: 1)
                    }
                    .accessibilityLabel("\(preset.title)，\(preset.modelEditionTitle)")
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func effectLevelTitle(_ level: Int) -> String {
        switch level {
        case 0:
            "高"
        case 1:
            "较高"
        case 2:
            "中"
        case 3:
            "低"
        default:
            "自定义（\(level)）"
        }
    }

    private func engineGraphicsLevelTitle(_ level: Int) -> String {
        switch level {
        case 1, 2:
            "低（\(level)）"
        case 3, 4:
            "中（\(level)）"
        case 5, 6:
            "高（\(level)）"
        case 7, 8:
            "极高（\(level)）"
        default:
            String(level)
        }
    }

    private func integerString(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func reloadSettings() async {
        guard let bottleURL else {
            settings = JX3QualityConfigValues()
            isLoadingSettings = false
            return
        }

        let configURL = JX3ConfigPresetImporter.configURL(in: bottleURL)
        isLoadingSettings = true

        let loadedSettings = await Task.detached(priority: .userInitiated) {
            JX3QualityConfigValues(configURL: configURL)
        }.value

        guard !Task.isCancelled else { return }
        settings = loadedSettings
        modelEdition = configuredModelEdition(
            at: configURL,
            fallbackFor: bottleURL
        )
        isLoadingSettings = false
        statusMessage = nil
        errorMessage = nil
    }

    private func scheduleAutoApply() {
        guard !isLoadingSettings, !isApplying, let bottleURL else {
            return
        }

        autoApplyTask?.cancel()
        let pendingSettings = settings
        autoApplyTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await applyCurrentSettings(pendingSettings, in: bottleURL)
        }
    }

    private func applyCurrentSettings(
        _ pendingSettings: JX3QualityConfigValues,
        in bottleURL: URL
    ) async {
        isApplying = true
        statusMessage = nil
        errorMessage = nil
        defer { isApplying = false }

        do {
            let configURL = JX3ConfigPresetImporter.configURL(in: bottleURL)
            let updates = pendingSettings.updates
            let confirmedSettings = try await Task.detached(priority: .utility) {
                guard try OnlineGameInitialConfiguration.enforceINIValues(
                    at: configURL,
                    updates: updates
                ) else {
                    throw JX3QualitySettingsError.configNotFound
                }

                let confirmation = JX3INIReader(url: configURL)
                guard updates.allSatisfy({ update in
                    confirmation.string(update.section, update.key) == update.value
                }) else {
                    throw JX3QualitySettingsError.writeNotConfirmed
                }

                return JX3QualityConfigValues(configURL: configURL)
            }.value
            guard !Task.isCancelled else { return }
            settings = confirmedSettings
            OnlineGameInitialConfiguration.startPolling(for: bottleURL)
            statusMessage = "已写入当前 Games 容器。"
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyOfficialPreset(_ preset: JX3OfficialQualityPreset) {
        guard let sourceURL = BundledOnlineGameResources.resourceURL(
            named: preset.resourceName
        ) else {
            errorMessage = "App 内未找到官方 \(preset.title) 画质预设。"
            statusMessage = nil
            return
        }
        applyPreset(
            from: sourceURL,
            displayName: preset.title,
            modelEdition: preset.modelEdition
        )
    }

    private func restoreProcyonPreset() {
        guard let sourceURL = BundledOnlineGameResources.resourceURL(
            named: JX3ConfigPresetImporter.recommendedConfigResourceName
        ) else {
            errorMessage = "App 内未找到 Arclume 内置画质预设。"
            statusMessage = nil
            return
        }
        applyPreset(
            from: sourceURL,
            displayName: "Arclume 内置画质预设",
            modelEdition: .flagship
        )
    }

    private func applyPreset(
        from sourceURL: URL,
        displayName: String,
        modelEdition: JX3ModelEdition
    ) {
        guard let bottleURL else {
            errorMessage = "请先选择剑网3使用的 Bottle。"
            statusMessage = nil
            return
        }

        isApplying = true
        statusMessage = nil
        errorMessage = nil
        defer { isApplying = false }

        do {
            let result = try JX3ConfigPresetImporter.importPreset(
                from: sourceURL,
                into: bottleURL
            )
            settings = JX3QualityConfigValues(configURL: result.configURL)
            self.modelEdition = modelEdition
            storeModelEdition(modelEdition, for: bottleURL)
            isLoadingSettings = false
            OnlineGameInitialConfiguration.startPolling(for: bottleURL)

            statusMessage = "已应用 \(displayName)。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configuredModelEdition(
        at configURL: URL,
        fallbackFor bottleURL: URL
    ) -> JX3ModelEdition {
        let reader = JX3INIReader(url: configURL)
        if reader.bool("UIVideoSetting", "HDRepresent", default: false) {
            return .flagship
        }

        return UserDefaults.standard.string(forKey: modelEditionDefaultsKey(for: bottleURL))
            .flatMap(JX3ModelEdition.init(rawValue:))
            ?? .flagship
    }

    private func storeModelEdition(_ edition: JX3ModelEdition, for bottleURL: URL) {
        UserDefaults.standard.set(edition.rawValue, forKey: modelEditionDefaultsKey(for: bottleURL))
    }

    private func modelEditionDefaultsKey(for bottleURL: URL) -> String {
        "Procyon.JX3Quality.modelEdition.\(bottleURL.standardizedFileURL.path)"
    }

}

private struct JX3DraftSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String

    @State private var draftValue: Double
    @State private var isEditing = false

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatter: @escaping (Double) -> String
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.formatter = formatter
        self._draftValue = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .foregroundStyle(.white.opacity(0.84))
                Spacer()
                Text(formatter(draftValue))
                    .foregroundStyle(.procyonSecondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { draftValue },
                    set: { draftValue = normalized($0) }
                ),
                in: range,
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        value = normalized(draftValue)
                    }
                }
            )
            .tint(.procyonSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onAppear {
            draftValue = value
        }
        .onChange(of: draftValue) { _, newValue in
            if !isEditing {
                value = normalized(newValue)
            }
        }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                draftValue = newValue
            }
        }
    }

    private func normalized(_ candidate: Double) -> Double {
        let steppedValue = ((candidate - range.lowerBound) / step).rounded() * step
            + range.lowerBound
        return min(range.upperBound, max(range.lowerBound, steppedValue))
    }
}
