import Foundation

nonisolated struct JX3INIKey: Hashable, Sendable {
    let section: String
    let key: String

    init(section: String, key: String) {
        self.section = section.lowercased()
        self.key = key.lowercased()
    }
}

nonisolated struct JX3INIReader: Sendable {
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
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
            )
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

nonisolated enum JX3Antialiasing: String, CaseIterable, Identifiable, Sendable {
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
        self == .dlss || self == .fsr || self == .nis
    }
}

nonisolated enum JX3EffectCullDistance: String, CaseIterable, Identifiable, Sendable {
    case near
    case medium
    case far
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .near:
            "近"
        case .medium:
            "中"
        case .far:
            "远"
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
        case .medium:
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

nonisolated enum JX3QualityConfigAntialiasing {
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

nonisolated struct JX3QualityConfigValues: Equatable, Sendable {
    var frameRateLimit = 67
    var playerModelLimit = 40
    var npcModelLimit = 50
    var clientSFXLimit = 1000
    var screenSizeLimitedRate = 1.0

    var enableFabric = true
    var enableSkillOptimization = true
    var enableLensLight = true
    var enableWeather = false
    var enableDayNightCycle = false
    var enableSeasonalVariation = false
    var enableCombi = false
    var showOutline = true
    var campUniform = false

    var dungeonOptimization = true
    var ownEffectLevel = 2
    var otherEffectLevel = 3
    var ownEffectIntensity = 1.0
    var otherEffectIntensity = 1.0
    var ownEffectLight = 1.0
    var otherEffectLight = 1.0
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
    var lightShaftBloom = false
    var lightShaftOcclusion = false
    var volumetricFog = false
    var screenSpaceReflection = true
    var fullScreenSharpen = false
    var reflectionEnhancement = false

    var lightShafts: Bool {
        get { lightShaftBloom || lightShaftOcclusion }
        set {
            lightShaftBloom = newValue
            lightShaftOcclusion = newValue
        }
    }

    var antialiasing: JX3Antialiasing = .dlss
    var upscaleMode = 0
    // Preserve the client's positive DLSS option instead of reducing every mode to 1.
    // This is separate from machine_config.ini's DLSS capability declaration.
    private var dlssOption = 1
    private var dlssSharpness = 0.0
    private var fsrSharpness = 0.0
    private var nisSharpness = 0.0

    var sharpness: Double {
        get {
            switch antialiasing {
            case .fsr: fsrSharpness
            case .nis: nisSharpness
            default: dlssSharpness
            }
        }
        set {
            switch antialiasing {
            case .fsr: fsrSharpness = newValue
            case .nis: nisSharpness = newValue
            default: dlssSharpness = newValue
            }
        }
    }

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
        enableWeather = ini.bool("UIVideoSetting", "EnableWeather", default: enableWeather)
        enableDayNightCycle = ini.bool("KG3DENGINE", "bEnableDayNightCycle", default: enableDayNightCycle)
        enableSeasonalVariation = ini.bool("KG3DENGINE", "bEnableSeasonalVariation", default: enableSeasonalVariation)
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
        ownEffectLight = ini.double("ENGINEOPTION", "MyEffectLight", default: ownEffectLight)
        otherEffectLight = ini.double("ENGINEOPTION", "OtherEffectLight", default: otherEffectLight)
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
        lightShaftBloom = ini.bool("KG3DENGINE", "bEnableRC_LightShaftBloom", default: lightShaftBloom)
        lightShaftOcclusion = ini.bool("KG3DENGINE", "bEnableRC_LightShaftOcclusion", default: lightShaftOcclusion)
        volumetricFog = ini.bool("KG3DENGINE", "bEnableVolumetricHeightFog", default: volumetricFog)
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
        dlssOption = max(1, ini.int("KG3DENGINE", "AAOPTION_DLSSOption", default: 1))
        upscaleMode = ini.int("KG3DENGINE", "FSR2Option", default: upscaleMode)
        dlssSharpness = ini.double("KG3DENGINE", "AAOPTION_DLSSParam", default: 0)
        fsrSharpness = ini.double("KG3DENGINE", "FSR2Sharpnees", default: 0)
        nisSharpness = ini.double("KG3DENGINE", "NISSharpness", default: 0)
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
            update("UIVideoSetting", "EnableWeather", boolString(enableWeather)),
            update("KG3DENGINE", "bEnableDayNightCycle", boolString(enableDayNightCycle)),
            update("KG3DENGINE", "bEnableSeasonalVariation", boolString(enableSeasonalVariation)),
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
            update("ENGINEOPTION", "MyEffectLight", decimalString(ownEffectLight)),
            update("ENGINEOPTION", "OtherEffectAlpha", decimalString(otherEffectIntensity)),
            update("ENGINEOPTION", "OtherEffectLight", decimalString(otherEffectLight)),
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
            update("KG3DENGINE", "bEnableRC_LightShaftBloom", boolString(lightShaftBloom)),
            update("KG3DENGINE", "bEnableRC_LightShaftOcclusion", boolString(lightShaftOcclusion)),
            update("KG3DENGINE", "bEnableVolumetricHeightFog", boolString(volumetricFog)),
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
            update("KG3DENGINE", "AAOPTION_DLSSOption", intString(antialiasing == .dlss ? dlssOption : 0)),
            update("KG3DENGINE", "EnableNIS", boolString(antialiasing == .nis)),
            update("KG3DENGINE", "EnableFSR", boolString(antialiasing == .fsr)),
            update("KG3DENGINE", "EnableFSR2", boolString(antialiasing == .fsr)),
            update("KG3DENGINE", "FSR2Option", intString(upscaleMode)),
            update("KG3DENGINE", "AAOPTION_DLSSParam", decimalString(dlssSharpness)),
            update("KG3DENGINE", "FSR2Sharpnees", decimalString(fsrSharpness)),
            update("KG3DENGINE", "NISSharpness", decimalString(nisSharpness))
        ]
    }

    /// Only write edited controls. Unrelated (including unknown/new client) values
    /// must survive opening this panel and changing another quality setting.
    func updates(comparedTo baseline: Self) -> [OnlineGameInitialConfiguration.INIUpdate] {
        let previous = Dictionary(uniqueKeysWithValues: baseline.updates.map {
            (JX3INIKey(section: $0.section, key: $0.key), $0.value)
        })
        let antialiasingKeys: Set<String> = [
            "AAOPTION_EnableTXAA", "AAOPTION_EnableSMAA", "bEnableRC_SMAA",
            "AAOPTION_DLSSOption", "EnableNIS", "EnableFSR", "EnableFSR2"
        ]
        return updates.filter { update in
            // Switching algorithms must clear all competing enable flags, even if
            // the original config contained more than one enabled algorithm.
            if update.section == "KG3DENGINE", antialiasingKeys.contains(update.key) {
                return antialiasing != baseline.antialiasing
            }
            return previous[JX3INIKey(section: update.section, key: update.key)] != update.value
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
