#if DEBUG
import SwiftUI

enum MigrationPreviewStage: String, CaseIterable, Identifiable {
    case detected = "迁移询问"
    case checking = "正在检查"
    case ready = "检查通过"
    case progress = "正在迁移"
    case complete = "升级完成"
    case blocked = "检查未通过"
    case recovery = "中断恢复"
    case finalization = "收尾重试"
    var id: String { rawValue }

    @MainActor func model() -> UnifiedContainerMigrationModel {
        let model = UnifiedContainerMigrationModel(demonstrationOnly: true)
        model.inspected = true
        model.learnedDuringUpgrade = true
        switch self {
        case .detected: break
        case .checking: model.busy = true
        case .ready, .blocked:
            model.plan = .init(sources: ["WindowsGameWinePrefixes/Steam", "OnlineGameWinePrefixes/YY"],
                snapshots: [], files: [:], registries: [:], notices: [],
                conflicts: self == .blocked ? ["演示检查失败"] : [], bytes: 2_400_000_000)
        case .progress:
            model.busy = true; model.transferring = true
            model.progress = 0.62; model.progressLabel = "正在校验应用文件…"
        case .complete: model.completed = true
        case .recovery, .finalization:
            model.record = .init(version: 1, id: UUID(), sources: ["WindowsGameWinePrefixes/Steam"],
                phase: self == .recovery ? .copying : .complete)
            if self == .finalization { model.message = "升级收尾未完成。请退出 Windows 程序后重试。" }
        }
        return model
    }
}

/// Gallery-only navigation is outside the inert production view.
struct MigrationPreviewGallery: View {
    @State private var stage = MigrationPreviewStage.detected
    private var index: Int { MigrationPreviewStage.allCases.firstIndex(of: stage) ?? 0 }
    var body: some View {
        VStack(spacing: 0) {
            UnifiedContainerGate(preview: stage) { EmptyView() }.id(stage)
            Divider()
            HStack(spacing: 18) {
                Label("安全演示 · 不执行迁移", systemImage: "eye").foregroundStyle(.secondary)
                Spacer()
                Button("上一页") { move(-1) }.disabled(index == 0)
                Picker("页面", selection: $stage) {
                    ForEach(MigrationPreviewStage.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 200)
                Text("\(index + 1) / \(MigrationPreviewStage.allCases.count)").monospacedDigit()
                Button("下一页") { move(1) }.disabled(index == MigrationPreviewStage.allCases.count - 1)
            }
            .padding(18)
        }.preferredColorScheme(.dark)
    }
    private func move(_ delta: Int) {
        stage = MigrationPreviewStage.allCases[min(max(index + delta, 0), MigrationPreviewStage.allCases.count - 1)]
    }
}
#endif
