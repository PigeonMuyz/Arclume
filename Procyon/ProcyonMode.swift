//
//  ProcyonMode.swift
//  Procyon
//

import Combine
import Foundation

enum ProcyonMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case standard
    case jx3

    static let defaultsKey = "procyon.operatingMode.v1"

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
final class ProcyonModeStore: ObservableObject {
    @Published private(set) var selectedMode: ProcyonMode?

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: suiteName)) {
        self.defaults = defaults ?? .standard

        #if DEBUG
        if ProcessInfo.processInfo.environment["PROCYON_UI_TEST_RESET_MODE"] == "1" {
            self.defaults.removeObject(forKey: ProcyonMode.defaultsKey)
        }
        if let override = ProcessInfo.processInfo.environment["PROCYON_UI_TEST_MODE"],
           let mode = ProcyonMode(rawValue: override) {
            self.defaults.set(mode.rawValue, forKey: ProcyonMode.defaultsKey)
        }
        #endif

        let rawValue = self.defaults.string(forKey: ProcyonMode.defaultsKey)
        self.selectedMode = rawValue.flatMap(ProcyonMode.init(rawValue:))
    }

    func select(_ mode: ProcyonMode) {
        defaults.set(mode.rawValue, forKey: ProcyonMode.defaultsKey)
        selectedMode = mode
    }

    func clearSelection() {
        defaults.removeObject(forKey: ProcyonMode.defaultsKey)
        selectedMode = nil
    }
}
