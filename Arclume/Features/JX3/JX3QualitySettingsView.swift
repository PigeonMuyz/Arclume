//
//  JX3QualitySettingsView.swift
//  Arclume
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
    case lightShafts
    case volumetricFog
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
            "尚未找到剑网3客户端的 config.ini，请先在启动器中完成游戏下载并运行一次游戏。"
        case .writeNotConfirmed:
            "无法确认 config.ini 已写入，画质设置未标记为成功。"
        }
    }
}

private enum JX3ModelEdition: String, Sendable {
    case handDrawn
    case flagship
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


struct JX3QualitySettingsView: View {
    let bottleURL: URL?
    @State private var settings = JX3QualityConfigValues()
    @State private var savedSettings = JX3QualityConfigValues()
    @State private var modelEdition: JX3ModelEdition = .flagship
    @State private var selectedSection: JX3QualitySection = .performance
    @State private var isApplying = false
    @State private var isLoadingSettings = true
    @State private var hasGameConfig = false
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
                if isLoadingSettings {
                    settingsLoadingState
                } else if hasGameConfig {
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
        .frame(width: 760, height: 520, alignment: .topLeading)
        .controlSize(.small)
        .task {
            await reloadSettings()
        }
        .onChange(of: settings) { _, _ in
            scheduleAutoApply()
        }
        .onDisappear {
            autoApplyTask?.cancel()
            // Closing within the debounce window must not discard the last edit.
            if hasGameConfig, !isLoadingSettings, !isApplying, settings != savedSettings, let bottleURL {
                let pendingSettings = settings
                Task { @MainActor in
                    await applyCurrentSettings(pendingSettings, in: bottleURL)
                }
            }
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
                            ? .arclumeSecondary.opacity(0.22)
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
                    qualityToggle("雨雪开关", isOn: $settings.enableWeather)
                    qualityToggle("日夜循环", isOn: $settings.enableDayNightCycle)
                    qualityToggle("四季变换", isOn: $settings.enableSeasonalVariation)
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
                    effectSliderRow("自身透明度", value: $settings.ownEffectIntensity)
                    effectSliderRow("其他玩家透明度", value: $settings.otherEffectIntensity)
                    effectSliderRow("自身明暗度", value: $settings.ownEffectLight)
                    effectSliderRow("其他玩家明暗度", value: $settings.otherEffectLight)
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
                    pickerRow("植被密度", selection: $settings.foliageDensity) {
                        Text("低").tag(10)
                        Text("中").tag(25)
                        Text("高").tag(50)
                        Text("超高").tag(100)
                        if ![10, 25, 50, 100].contains(settings.foliageDensity) {
                            Text("自定义（\(settings.foliageDensity)）").tag(settings.foliageDensity)
                        }
                    }
                    pickerRow("阴影质量", selection: $settings.shadowType) {
                        Text("无").tag(0)
                        Text("中").tag(1)
                        Text("高").tag(2)
                        Text("超高").tag(3)
                        Text("低").tag(7)
                    }
                    pickerRow("水面精度", selection: $settings.waterEffectLevel) {
                        Text("超高").tag(0)
                        Text("高").tag(1)
                        Text("中").tag(2)
                        Text("低").tag(3)
                    }
                    pickerRow("阴影数量", selection: $settings.shadowQuantity) {
                        Text("低").tag(0)
                        Text("中").tag(40)
                        Text("高").tag(90)
                        Text("超高").tag(100)
                    }
                    pickerRow("远景显示", selection: farDisplayBinding) {
                        Text("低").tag(20_000)
                        Text("中").tag(50_000)
                        Text("高").tag(100_000)
                        Text("超高").tag(800_000)
                        if ![20_000, 50_000, 100_000, 800_000].contains(settings.farDisplayDistance) {
                            Text("自定义（\(settings.farDisplayDistance)）").tag(settings.farDisplayDistance)
                        }
                    }
                    HStack {
                        Text("物件细节")
                        Spacer()
                        Text("由游戏控制").foregroundStyle(.secondary)
                    }
                    .help("尚未确认独立配置键；不会再将物件细节写入整体画质档位 nEngineGraphicsLevel。")
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
                        "体积光",
                        isOn: $settings.lightShafts,
                        enabled: postEffectPolicy.allows(.lightShafts)
                    )
                    qualityToggle(
                        "体积雾",
                        isOn: $settings.volumetricFog,
                        enabled: postEffectPolicy.allows(.volumetricFog)
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
                        // FSR2Option is not a DLSS mode. Do not offer an apparently
                        // working DLSS picker until its client mapping is verified.
                        if settings.antialiasing == .fsr {
                            pickerRow("FSR 档位", selection: $settings.upscaleMode) {
                                Text("超性能").tag(0)
                                Text("性能").tag(1)
                                Text("均衡").tag(2)
                                Text("质量").tag(3)
                                if !(0...3).contains(settings.upscaleMode) {
                                    Text("当前值（\(settings.upscaleMode)）").tag(settings.upscaleMode)
                                }
                            }
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
            .arclumeAccent.mix(with: .black, by: 0.66).opacity(0.78),
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
                    ? .arclumeSecondary
                    : .white.opacity(isAvailable ? 0.82 : 0.28)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? .arclumeSecondary.opacity(0.16)
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

    private func effectSliderRow(_ title: String, value: Binding<Double>) -> some View {
        sliderRow(
            title,
            value: value,
            range: 0...1,
            step: 0.01,
            formatter: { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) }
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

    private func integerString(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func reloadSettings() async {
        guard let bottleURL else {
            settings = JX3QualityConfigValues()
            isLoadingSettings = false
            return
        }

        let configURL = JX3GameConfiguration.configURL(in: bottleURL)
        isLoadingSettings = true
        hasGameConfig = false
        guard FileManager.default.isReadableFile(atPath: configURL.path) else {
            isLoadingSettings = false
            errorMessage = JX3QualitySettingsError.configNotFound.localizedDescription
            return
        }

        let loadedSettings = await Task.detached(priority: .userInitiated) {
            JX3QualityConfigValues(configURL: configURL)
        }.value

        guard !Task.isCancelled else { return }
        savedSettings = loadedSettings
        settings = loadedSettings
        modelEdition = configuredModelEdition(
            at: configURL,
            fallbackFor: bottleURL
        )
        isLoadingSettings = false
        hasGameConfig = true
        statusMessage = nil
        errorMessage = nil
    }

    private func scheduleAutoApply() {
        guard hasGameConfig, !isLoadingSettings, !isApplying, let bottleURL else {
            return
        }

        autoApplyTask?.cancel()
        guard settings != savedSettings else { return }
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
            let configURL = JX3GameConfiguration.configURL(in: bottleURL)
            let updates = pendingSettings.updates(comparedTo: savedSettings)
            guard !updates.isEmpty else { return }
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
            savedSettings = confirmedSettings
            settings = confirmedSettings
            statusMessage = "已写入当前 Games 容器。"
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configuredModelEdition(
        at configURL: URL,
        fallbackFor bottleURL: URL
    ) -> JX3ModelEdition {
        let reader = JX3INIReader(url: configURL)
        if reader.string("UIVideoSetting", "HDRepresent") != nil {
            return reader.bool("UIVideoSetting", "HDRepresent", default: false)
                ? .flagship : .handDrawn
        }

        return UserDefaults.standard.string(forKey: modelEditionDefaultsKey(for: bottleURL))
            .flatMap(JX3ModelEdition.init(rawValue:))
            ?? .flagship
    }

    private func modelEditionDefaultsKey(for bottleURL: URL) -> String {
        "Arclume.JX3Quality.modelEdition.\(bottleURL.standardizedFileURL.path)"
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
                    .foregroundStyle(.arclumeSecondary)
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
            .tint(.arclumeSecondary)
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
