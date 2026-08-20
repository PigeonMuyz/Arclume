//
//  ArclumeMode.swift
//  Arclume
//

import Combine
import Foundation

enum ArclumeMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case standard
    case jx3

    static let defaultsKey = "arclume.operatingMode.v1"
    static let legacyDefaultsKey = "procyon.operatingMode.v1"

    var id: Self { self }

    var title: String {
        switch self {
        case .standard:
            "普通模式"
        case .jx3:
            "剑网3模式"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            "Steam + 自定义游戏"
        case .jx3:
            "SeasunGame / 剑网3"
        }
    }

    var description: String {
        switch self {
        case .standard:
            "扫描 Steam 游戏库，也可以添加自定义游戏。"
        case .jx3:
            "只扫描 SeasunGame，只识别 SeasunGame 启动器和剑网3。"
        }
    }

    var features: [String] {
        switch self {
        case .standard:
            [
                "识别 Steam 游戏库",
                "支持添加自定义游戏",
                "支持原生 Mac 应用"
            ]
        case .jx3:
            [
                "只扫描 SeasunGame.exe",
                "自动识别剑网3启动器",
                "不读取 Steam 游戏库"
            ]
        }
    }

    var systemImage: String {
        switch self {
        case .standard:
            "gamecontroller.fill"
        case .jx3:
            "sparkles.tv.fill"
        }
    }

    var isOnlineGameMode: Bool {
        self == .jx3
    }

    static var persisted: Self? {
        guard let rawValue = UserDefaults(suiteName: suiteName)?
            .string(forKey: defaultsKey)
        else {
            return nil
        }
        return Self(rawValue: rawValue)
    }
}

@MainActor
final class ArclumeModeStore: ObservableObject {
    @Published private(set) var selectedMode: ArclumeMode?

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: suiteName)) {
        self.defaults = defaults ?? .standard

        #if DEBUG
        if ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_RESET_MODE"] == "1" {
            self.defaults.removeObject(forKey: ArclumeMode.defaultsKey)
        }
        if let override = ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_MODE"],
           let mode = ArclumeMode(rawValue: override) {
            self.defaults.set(mode.rawValue, forKey: ArclumeMode.defaultsKey)
        }
        #endif

        let rawValue = self.defaults.string(forKey: ArclumeMode.defaultsKey)
        self.selectedMode = rawValue.flatMap(ArclumeMode.init(rawValue:))
    }

    func select(_ mode: ArclumeMode) {
        defaults.set(mode.rawValue, forKey: ArclumeMode.defaultsKey)
        selectedMode = mode
    }

    func clearSelection() {
        defaults.removeObject(forKey: ArclumeMode.defaultsKey)
        selectedMode = nil
    }
}
