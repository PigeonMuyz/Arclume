import SwiftUI

struct PortableGreenPreparationView: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var plan: PortableGreenPreparation.Plan?
    @State private var result: PortableGreenPreparation.Result?
    @State private var error: String?
    @State private var busy = false
    @State private var previousRecovery: URL?
    private let owned = [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("应用绿色适配").font(.title2.bold())
            Text("\(game.name)：屏蔽规则中列出的广告、游戏推广与内置自动更新，后续仍可用新版压缩包替换更新。")
            Text("请先退出所有 Windows 程序。旧目录先移到恢复位置，不清空账号配置，不关闭日志，不执行 BAT、提权或注册命令。")
                .font(.callout).foregroundStyle(.secondary)
            if let plan {
                DisclosureGroup("查看 \(plan.targets.count) 个处理路径") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(plan.targets, id: \.path) { Text($0.path).font(.caption).textSelection(.enabled) }
                        }
                    }.frame(maxHeight: 160)
                }
            }
            if busy { ProgressView().controlSize(.small) }
            if let result {
                Text(result.error == nil ? "已处理 \(result.changed) 项；已经生效的项目不会重复处理。" : "已处理 \(result.changed) 项，其余未完成。")
            }
            if let recovery = result?.recovery ?? previousRecovery {
                HStack {
                    Button("打开恢复目录") { NSWorkspace.shared.open(recovery) }
                    Button("撤销此次适配") { restore(recovery) }.disabled(busy)
                }
            }
            if let message = error ?? result?.error { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("关闭") { dismiss() }.disabled(busy)
                Spacer()
                Button("应用适配") { apply() }.buttonStyle(.borderedProminent).disabled(busy || plan == nil)
            }
        }.padding(24).frame(width: 520).interactiveDismissDisabled(busy)
        .task {
            guard let executable = GameRemovalService.target(for: game), let bottle = game.installedBottleURL else { error = "无法确定软件目录。"; return }
            busy = true; defer { busy = false }
            do {
                plan = try await Task.detached { try PortableGreenPreparation.plan(executable: executable, bottle: bottle, ownedBottles: owned) }.value
                if let plan { previousRecovery = await Task.detached { PortableGreenPreparation.latestRecovery(plan) }.value }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func apply() {
        guard let plan else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            let next = await Task.detached { PortableGreenPreparation.apply(plan, ownedBottles: owned) }.value
            // Keep the prior recovery button after a no-op repeated application.
            var merged = next
            if merged.recovery == nil { merged.recovery = result?.recovery }
            result = merged
        }
    }

    private func restore(_ recovery: URL) {
        guard let plan else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await Task.detached { try PortableGreenPreparation.restore(recovery, bottle: plan.bottle, ownedBottles: owned) }.value
                result = nil
                previousRecovery = nil
            } catch { self.error = "撤销未全部完成：\(error.localizedDescription)。恢复目录仍保留。" }
        }
    }
}
