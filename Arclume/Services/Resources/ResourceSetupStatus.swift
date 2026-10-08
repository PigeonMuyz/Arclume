import Foundation

/// Shared, side-effect-free presentation state for onboarding and Settings.
nonisolated struct ResourceSetupStatus: Equatable, Sendable {
    enum Runtime: Equatable, Sendable {
        case missing
        case update(installed: String?)
        case repair
        case ready
    }
    let runtime: Runtime
    let targetVersion: String
    let missingComponents: [String]
    let componentCount: Int
    let downloadBytes: Int64
    let catalogAvailable: Bool
    let noticeID: String

    var isReady: Bool { catalogAvailable && runtime == .ready && missingComponents.isEmpty }
    var runtimeDetail: String {
        switch runtime {
        case .missing: "尚未安装 · \(targetVersion)"
        case .update(let installed): "可升级 · \(installed ?? "旧版本") → \(targetVersion)"
        case .repair: "需要修复 · \(targetVersion)"
        case .ready: "已就绪 · \(targetVersion)"
        }
    }
    var actionTitle: String {
        switch runtime {
        case .update: "升级运行时"
        case .repair: "修复运行时"
        case .missing: "下载运行时"
        case .ready: missingComponents.isEmpty ? "检查组件状态" : "下载缺失组件"
        }
    }
    var componentDetail: String {
        guard catalogAvailable else { return "无法读取组件清单" }
        return missingComponents.isEmpty ? "已就绪 · \(componentCount) 项" : "待补齐 · \(missingComponents.joined(separator: "、"))"
    }
    static func shouldOfferUpgrade(completedOnboarding: Bool, acknowledgedNotice: String, status: Self,
                                   reviewedRuntimeChoice: Bool = true) -> Bool {
        completedOnboarding && (!reviewedRuntimeChoice || (!status.isReady && acknowledgedNotice != status.noticeID))
    }
}
