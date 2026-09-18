import SwiftUI
import AppKit
import Combine

@MainActor
final class UnifiedContainerMigrationModel: ObservableObject {
    static let shared = UnifiedContainerMigrationModel()
    @Published var ready = false
    @Published var inspected = false
    @Published var learnedDuringUpgrade = false
    @Published var busy = false
    @Published var plan: UnifiedContainerMigration.Plan?
    @Published var record: UnifiedContainerMigration.Journal?
    @Published var message: String?
    @Published var completed = false
    @Published var transferring = false
    @Published var progress: Double = 0
    @Published var progressLabel = "准备迁移"
    private var diagnostic: String?
    private let migration = UnifiedContainerMigration(root: ARCLUME_SUPPORT_FOLDER_URL)
    private let demonstrationOnly: Bool
    init(demonstrationOnly: Bool = false) { self.demonstrationOnly = demonstrationOnly }

    func inspect() {
        guard !demonstrationOnly, !busy else { return }
        defer { inspected = true }
        do {
            record = try migration.journal()
            ready = try !migration.requiresMigration()
        } catch {
            diagnostic = error.localizedDescription
            message = "暂时无法检查旧环境。请退出其他 Windows 程序后重试；原数据不会改变。"
        }
    }
    var needsFinalization: Bool {
        record.map { [.complete, .cleaning].contains($0.phase) } == true
    }
    func finishUpgrade() {
        guard !demonstrationOnly, !busy else { return }
        busy = true; transferring = true; message = nil
        progress = 1; progressLabel = "正在完成升级…"
        let engine = migration
        Task {
            do {
                record = try await Task.detached {
                    try engine.finalize(preferencesDomain: suiteName, checkIdle: Self.checkIdle)
                }.value
                completed = true
            } catch {
                record = try? engine.journal()
                diagnostic = error.localizedDescription
                message = "升级收尾未完成。请退出 Windows 程序后重试。"
            }
            busy = false; transferring = false
        }
    }
    private nonisolated static func checkIdle() throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.pigeonmuyz.arclume")
            .allSatisfy({ $0.processIdentifier == ProcessInfo.processInfo.processIdentifier }) else {
            throw UnifiedContainerMigration.Failure(message: "请先退出其他 Arclume 实例。")
        }
        try GameAssociatedDataService.requireRegistryIdle()
    }
    func check() {
        guard !demonstrationOnly, !busy else { return }
        busy = true; message = "正在检查文件、注册表和盘符；旧容器不会改变。"; plan = nil
        let engine = migration
        Task {
            do {
                plan = try await Task.detached { try engine.preflight(checkIdle: Self.checkIdle) }.value
                message = nil
            } catch {
                diagnostic = error.localizedDescription
                message = "检查未完成，请先退出其他 Arclume 和 Windows 程序，再重试。原数据未改变。"
            }
            busy = false
        }
    }
    func start() {
        guard !demonstrationOnly, !busy, let plan, plan.conflicts.isEmpty else { return }
        busy = true; transferring = true; progress = 0; progressLabel = "准备迁移"; message = nil
        let engine = migration
        let report: @Sendable (Double, String) -> Void = { value, label in
            Task { @MainActor [weak self] in self?.progress = value; self?.progressLabel = label }
        }
        Task {
            do {
                record = try await Task.detached {
                    _ = try engine.migrate(plan, preferencesDomain: suiteName, checkIdle: Self.checkIdle, progress: report)
                    report(1, "正在完成升级…")
                    return try engine.finalize(preferencesDomain: suiteName, checkIdle: Self.checkIdle)
                }.value
                completed = true; message = nil
            } catch {
                record = try? engine.journal()
                diagnostic = error.localizedDescription
                self.plan = nil
                message = needsFinalization ? "升级收尾未完成，请重试完成升级。" : "本次迁移未完成。原始内容仍保留，可恢复原环境后重试。"
            }
            busy = false
            transferring = false
        }
    }
    func restore() {
        guard !demonstrationOnly, !busy else { return }
        busy = true; message = "正在恢复原容器和偏好。迁移副本会保留，不删除其中的数据。"
        let engine = migration
        Task {
            do {
                try await Task.detached { try engine.rollback(preferencesDomain: suiteName, checkIdle: Self.checkIdle) }.value
                record = try engine.journal(); plan = nil; completed = false
                message = "旧容器已恢复。可以重新检查，或退出后使用旧版 Arclume。"
            } catch {
                diagnostic = error.localizedDescription
                message = "暂时无法完成恢复。请退出其他 Windows 程序后重试，或保存诊断报告以便检查。"
            }
            busy = false
        }
    }
    func showRecovery() {
        guard !demonstrationOnly else { return }
        if let record { NSWorkspace.shared.open(migration.recoveryURL(record)) }
    }
    func exportDiagnostics() {
        guard !demonstrationOnly else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Arclume-迁移检查.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let lines = [diagnostic].compactMap { $0 } + (plan?.sources ?? []) + (plan?.conflicts ?? []) + (plan?.notices ?? [])
        do { try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { message = "无法保存诊断报告，请选择其他位置。" }
    }
}

/// Do not instantiate ContentView/AppGlobals until the prefix transaction is settled.
struct UnifiedContainerGate<Content: View>: View {
    @StateObject private var model: UnifiedContainerMigrationModel
    private var isPreview = false
    @State private var started = false
    @State private var confirmMigration = false
    @State private var confirmRestore = false
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        _model = StateObject(wrappedValue: UnifiedContainerMigrationModel.shared)
        self.content = content
    }

    #if DEBUG
    init(preview: MigrationPreviewStage, @ViewBuilder content: @escaping () -> Content) {
        _model = StateObject(wrappedValue: preview.model())
        _started = State(initialValue: preview != .detected)
        isPreview = true
        self.content = content
    }
    #endif

    private var needsRecovery: Bool {
        model.record.map { [.copying, .switching].contains($0.phase) } == true && !model.completed
    }
    private var step: Int {
        if model.completed { return 3 }
        if model.transferring || needsRecovery || model.needsFinalization { return 2 }
        return started || model.plan != nil ? 1 : 0
    }

    var body: some View {
        Group {
            if !model.inspected { ProgressView().frame(width: 1100, height: 650) }
            else if model.ready { content() }
            else if !model.learnedDuringUpgrade && model.record == nil && model.message == nil {
                UpgradeTeachingView { model.learnedDuringUpgrade = true }
                    .frame(width: 1100, height: 650)
            }
            else {
                OnboardingStage(title: "升级 Arclume", showsBrand: step == 0) {
                    stageContent
                } actions: {
                    Button("暂不迁移并退出") { if !isPreview { NSApp.terminate(nil) } }.disabled(model.busy)
                    Spacer()
                    actions
                }
                .modifier(UpgradeButtonStyle())
                .controlSize(.large)
                .frame(width: 1100, height: 650)
            }
        }
        .allowsHitTesting(!isPreview)
        .task { if !isPreview { model.inspect() } }
        .confirmationDialog("将旧容器安全合并为 ALBottles？", isPresented: $confirmMigration, titleVisibility: .visible) {
            Button("开始迁移") { model.start() }
            Button("取消", role: .cancel) { }
        } message: { Text("校验成功后切换到新环境，并自动移除旧副本。升级期间请勿启动 Windows 应用。") }
        .confirmationDialog("恢复迁移前的容器和设置？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("恢复旧容器") { model.restore() }
            Button("取消", role: .cancel) { }
        } message: { Text("当前迁移副本会保留在恢复目录，不会删除。恢复后需重新迁移才能进入新版架构。") }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("升级 Arclume").font(.title2.weight(.semibold)).padding(.bottom, 12)
            ForEach(Array(["统一应用环境", "检查迁移条件", "安全迁移", "升级完成"].enumerated()), id: \.offset) { index, title in
                HStack(spacing: 10) {
                    Image(systemName: index < step ? "checkmark.circle.fill" : index == step ? "largecircle.fill.circle" : "circle")
                        .frame(width: 22).foregroundStyle(index <= step ? Color.accentColor : .secondary)
                    Text(title).fontWeight(index == step ? .semibold : .regular)
                        .foregroundStyle(index > step ? .secondary : .primary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var stageContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.completed {
                Label("升级完成", systemImage: "checkmark.circle.fill")
                    .font(.title2.weight(.semibold))
            } else if model.transferring {
                Text("正在升级 Arclume").font(.title2.weight(.semibold))
                ProgressView(value: model.progress) { Text(model.progressLabel) }
                Text("请保持 Arclume 打开，暂时不要启动 Windows 应用。")
                    .font(.callout).foregroundStyle(.secondary)
            } else if model.needsFinalization {
                Text("继续完成升级").font(.title2.weight(.semibold))
            } else if needsRecovery {
                header("恢复上次迁移", detail: "上次迁移没有正常结束。请先恢复原环境，再继续升级。")
                if model.busy { ProgressView("正在恢复…") }
                Button("查看恢复副本") { model.showRecovery() }.disabled(model.busy)
            } else if step == 0 {
                header("检测到旧版 Arclume 数据", detail: "是否迁移已有应用和配置？迁移后使用统一的 ALBottles 环境。")
                Text("请先退出正在运行的 Windows 程序。下一步只会检查，不会立即迁移。")
                    .font(.callout).foregroundStyle(.secondary)
            } else if model.busy {
                header("正在检查旧环境", detail: "自动检查文件、空间和应用状态，无需手动整理。")
                ProgressView("正在检查…")
            } else if let plan = model.plan {
                if plan.conflicts.isEmpty {
                    header("可以开始迁移", detail: "已完成检查，旧配置将由 Arclume 自动整理。")
                    Label("\(plan.sources.count) 个环境合并为 ALBottles", systemImage: "shippingbox")
                    Label("临时需要 \(ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .file)) 空间", systemImage: "internaldrive")
                } else {
                    header("有应用数据需要进一步检查", detail: "为避免覆盖已有应用数据，本次未执行迁移。你可以保存诊断报告以便处理，原环境保持不变。")
                    Button("保存诊断报告…") { model.exportDiagnostics() }
                }
            } else {
                header("检查尚未完成", detail: "原环境和应用数据保持不变。")
            }
            if let message = model.message, !model.busy {
                Text(message).font(.callout).foregroundStyle(.secondary)
                if model.plan == nil { Button("保存诊断报告…") { model.exportDiagnostics() } }
            }
        }
    }

    private func header(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var actions: some View {
        if model.completed {
            Button("进入 Arclume") { model.ready = true }.modifier(UpgradeButtonStyle(prominent: true))
        } else if model.busy {
            Text(model.transferring ? "正在迁移…" : "请稍候…").foregroundStyle(.secondary)
        } else if model.needsFinalization {
            Button("重试完成升级") { model.finishUpgrade() }.modifier(UpgradeButtonStyle(prominent: true))
        } else if needsRecovery {
            Button("恢复原环境…") { confirmRestore = true }.modifier(UpgradeButtonStyle(prominent: true))
        } else if step == 0 {
            Button("继续") { started = true; model.check() }.modifier(UpgradeButtonStyle(prominent: true))
        } else {
            Button("上一步") { started = false; model.plan = nil; model.message = nil }
            if model.plan?.conflicts.isEmpty == true {
                Button("开始迁移…") { confirmMigration = true }.modifier(UpgradeButtonStyle(prominent: true))
            } else {
                Button("重新检查") { model.check() }.modifier(UpgradeButtonStyle(prominent: true))
            }
        }
    }
}

/// Native styles retain keyboard, accessibility and Reduce Transparency behavior.
private struct UpgradeButtonStyle: ViewModifier {
    var prominent = false

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}
