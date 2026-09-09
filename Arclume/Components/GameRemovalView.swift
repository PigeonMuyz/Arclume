import SwiftUI

struct GameRemovalView: View {
    let game: Game
    @EnvironmentObject private var library: LibraryPageGlobals
    @Environment(\.dismiss) private var dismiss
    @State private var gamePlan: GameRemovalPlan?
    @State private var launcherPlan: LauncherRemovalPlan?
    @State private var data: [String: [GameDataItem]] = [:]
    @State private var removeAll = false
    @State private var includeGames = false
    @State private var busy = true
    @State private var error: String?
    @State private var result: GameCleanupResult?
    @State private var removedLauncher: URL?

    private var selectedItems: [GameDataItem] {
        removeAll && (gamePlan != nil || includeGames) ? data.values.flatMap { $0 } : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result == nil ? "卸载 \(game.name)？" : (error == nil ? "已完成" : "未全部完成")).font(.title2)
            if busy { ProgressView("正在检查…") }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            if result == nil, gamePlan != nil || launcherPlan != nil {
                Picker("移除方式", selection: $removeAll) {
                    Text("仅卸载，保留游戏数据").tag(false)
                    Text("移除全部，包括已识别的本地数据").tag(true)
                }.pickerStyle(.radioGroup).disabled(busy)

                if let launcherPlan, launcherPlan.hasGames {
                    Text("卸载启动器后，关联游戏可能无法启动或进行大版本更新。")
                        .font(.callout).foregroundStyle(.orange)
                    Toggle("一并移除关联游戏（\(launcherPlan.games.count)）", isOn: $includeGames)
                        .disabled(busy || !launcherPlan.canRemoveGames)
                    Text(launcherPlan.games.map { plan in
                        GameAdaptationRules.all.first { $0.directory(in: plan.bottle).path == plan.directory.path }?.name ?? plan.directory.lastPathComponent
                    }.joined(separator: "、"))
                        .font(.caption).foregroundStyle(.secondary)
                    if !launcherPlan.unknownGames.isEmpty {
                        Text("有未识别的游戏内容，将保留，暂不支持一并移除。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(launcherPlan != nil && !includeGames ? "关联游戏及其数据会保留。" : (removeAll ? "会清除所选游戏的本地设置和登录信息；云端账号与未选中的游戏不受影响。" : "保留存档、设置和登录信息，方便以后重新安装。"))
                    .font(.footnote).foregroundStyle(.secondary)
                if selectedItems.contains(where: { $0.category == .registry }) {
                    Text("清理游戏设置前，请退出所有 Wine 程序。")
                        .font(.footnote).foregroundStyle(.orange)
                }
                DisclosureGroup("查看详细信息") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let gamePlan { detail(gamePlan.directory.path, bytes: gamePlan.bytes) }
                            if let launcherPlan {
                                ForEach(launcherPlan.entries, id: \.url) { detail($0.url.path, bytes: $0.bytes) }
                                if includeGames {
                                    ForEach(launcherPlan.games, id: \.directory) { detail($0.directory.path, bytes: $0.bytes) }
                                }
                                if !launcherPlan.retainedEntries.isEmpty { Text("未识别的启动器目录内容保留。").font(.caption) }
                            }
                            ForEach(selectedItems) { detail($0.displayPath, bytes: $0.bytes) }
                            Text("文件移至废纸篓；注册表保存私有恢复片段。共享、未知数据及整个 Wine 容器不会删除。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxHeight: 190)
                }
            }
            if let result {
                Text("已处理 \(result.completed.count) 项。文件可从废纸篓恢复。")
                    .font(.callout)
                DisclosureGroup("查看结果") {
                    ScrollView {
                        Text((result.completed + result.recoveryURLs.map { "注册表恢复片段：" + $0.path }
                            + [result.recoveryURL].compactMap { $0.map { "注册表恢复片段：" + $0.path } }).joined(separator: "\n"))
                            .font(.caption).textSelection(.enabled)
                    }.frame(maxHeight: 150)
                }
                if result.bodyRemoved, let gamePlan, gamePlan.launcher != nil, removedLauncher == nil {
                    Button("也移除不再使用的启动器", role: .destructive) { removeUnusedLauncher(gamePlan) }.disabled(busy)
                }
            }
            HStack {
                Button(result == nil ? "取消" : "关闭") { dismiss() }.disabled(busy)
                Spacer()
                if result == nil, gamePlan != nil || launcherPlan != nil {
                    Button(removeAll ? "移除全部" : "卸载", role: .destructive) { remove() }.disabled(busy)
                }
            }
        }
        .padding(24).frame(width: 500)
        .interactiveDismissDisabled(busy)
        .task { await loadPreview() }
        .onDisappear { removeLibraryEntries() }
    }

    private func detail(_ path: String, bytes: Int64) -> some View {
        Text("\(path) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
            .font(.caption).textSelection(.enabled)
    }

    private func loadPreview() async {
        defer { busy = false }
        guard let executable = GameRemovalService.target(for: game), let bottle = game.installedBottleURL else {
            error = GameRemovalError.unsupported.localizedDescription; return
        }
        let linked = library.customAddedGames.compactMap(GameRemovalService.target)
        do {
            let preview = try await Task.detached {
                let owned = [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL]
                if GameAdaptationRules.matching(executable)?.kind == "launcher" {
                    let plan = try LauncherRemovalService.plan(executable: executable, bottle: bottle, ownedBottles: owned, linkedExecutables: linked)
                    let data = try Dictionary(uniqueKeysWithValues: plan.games.map { ($0.directory.path, try GameAssociatedDataService.scan($0)) })
                    return (Optional<GameRemovalPlan>.none, Optional(plan), data)
                }
                let plan = try GameRemovalService.plan(executable: executable, bottle: bottle, ownedBottles: owned, linkedExecutables: linked)
                return (Optional(plan), Optional<LauncherRemovalPlan>.none, [plan.directory.path: try GameAssociatedDataService.scan(plan)])
            }.value
            gamePlan = preview.0; launcherPlan = preview.1; data = preview.2
        } catch { self.error = error.localizedDescription }
    }

    private func remove() {
        busy = true; error = nil
        let linked = library.customAddedGames.compactMap(GameRemovalService.target)
        let gamePlan = gamePlan, launcherPlan = launcherPlan, data = data, all = removeAll, together = includeGames
        Task {
            defer { busy = false }
            let outcome = await Task.detached {
                if let launcherPlan {
                    return LauncherRemovalService.clean(launcherPlan, removeGames: together, removeAllData: all, data: data, linkedExecutables: linked)
                }
                guard let gamePlan else { return GameCleanupResult(error: GameRemovalError.unsupported.localizedDescription) }
                let items = data[gamePlan.directory.path] ?? []
                return GameAssociatedDataService.clean(gamePlan, preview: items, selected: all ? Set(items.map(\.id)) : [], removeBody: true, linkedExecutables: linked)
            }.value
            result = outcome; error = outcome.error
            if outcome.bodyRemoved, let launcherPlan { removedLauncher = launcherPlan.directory }
        }
    }

    private func removeUnusedLauncher(_ gamePlan: GameRemovalPlan) {
        guard let root = gamePlan.launcher,
              let rule = GameAdaptationRules.all.first(where: { $0.kind == "launcher" && $0.directory(in: gamePlan.bottle) == root }) else { return }
        busy = true; error = nil
        let linked = library.customAddedGames.filter { $0.id != game.id }.compactMap(GameRemovalService.target)
        Task {
            defer { busy = false }
            do {
                let outcome = try await Task.detached {
                    let plan = try LauncherRemovalService.plan(executable: root.appendingPathComponent(rule.executable), bottle: gamePlan.bottle,
                        ownedBottles: [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL], linkedExecutables: linked)
                    guard !plan.hasGames else { throw GameRemovalError.changed }
                    return LauncherRemovalService.clean(plan, removeGames: false, removeAllData: false, data: [:], linkedExecutables: linked)
                }.value
                result?.completed += outcome.completed
                if outcome.bodyRemoved { removedLauncher = root }
                error = outcome.error
            } catch { self.error = error.localizedDescription }
        }
    }

    private func removeLibraryEntries() {
        let directories = result?.removedGameDirectories ?? []
        for entry in library.customAddedGames {
            guard let target = GameRemovalService.target(for: entry) else { continue }
            let path = target.standardizedFileURL.path
            let removedGame = directories.contains { path.hasPrefix($0.path + "/") }
            let removedLauncherEntry = removedLauncher.map { path.hasPrefix($0.path + "/") && !path.hasPrefix($0.path + "/games/") } ?? false
            if removedGame || removedLauncherEntry { library.deleteCustomAddedGame(game: entry) }
        }
    }
}
