import SwiftUI

struct GameShaderOptimizationView: View {
    let gameID: String
    let prefix: URL
    let executableName: String
    var launcherURL: URL? = nil
    @ObservedObject var library: LibraryPageGlobals
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @AppStorage("shaderOptimizationWorkers", store: UserDefaults(suiteName: suiteName)) private var workerPreference = 1
    @State private var progress: GameMetalShaderCache.Progress?
    @State private var remaining: Duration?
    @State private var operation: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var dxbcCount = 0
    @State private var readCount = 0

    private var gameRoot: URL? {
        GameDXBCPrecompile.gameRoot(gameID: gameID, launcher: launcherURL)
    }

    private var gameRunning: Bool {
        library.playingID == gameID || library.isLaunchingGame
            || (gameID == OnlineGameMode.jx3GameID && library.jx3RuntimeActivity.hasLiveWindowsProcess)
    }

    private var maximumWorkers: Int {
        min(GameMetalShaderCache.maximumWorkers, max(1, ProcessInfo.processInfo.activeProcessorCount))
    }

    private var workers: Int { min(maximumWorkers, max(1, workerPreference)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("优化 DXMT 着色器").font(.title2.weight(.semibold))
            if let progress {
                ProgressView(value: Double(progress.processed), total: Double(max(1, progress.total))) {
                    Text("正在优化着色器（\(progress.processed) / \(progress.total)）")
                }.accessibilityIdentifier("shaders.progress")
                if let remaining {
                    let formatted = remaining.formatted(.units(allowed: [.hours, .minutes, .seconds],
                                                               width: .abbreviated, maximumUnitCount: 2).locale(locale))
                    Text(L10n.format("About %@ remaining in this stage", formatted))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        .accessibilityIdentifier("shaders.remaining")
                }
            } else if refreshing {
                ProgressView {
                    LabeledContent("读取着色器数量", value: "\(readCount)")
                }
            } else {
                LabeledContent("读取着色器数量", value: "\(readCount)")
            }
            Stepper(value: Binding(get: { workers }, set: { workerPreference = $0 }), in: 1...maximumWorkers) {
                LabeledContent(L10n.string("Processing threads"), value: "\(workers)")
            }
            .disabled(operation != nil || maximumWorkers == 1)
            .accessibilityIdentifier("shaders.workers")
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("shaders.error")
            }
            HStack {
                Spacer()
                if operation != nil {
                    Button("取消") { operation?.cancel() }.accessibilityIdentifier("shaders.cancel")
                } else {
                    Button("开始优化", action: optimize)
                        .buttonStyle(.borderedProminent)
                        .disabled(refreshing || gameRunning || readCount == 0 || !GameMetalShaderCache.toolsAvailable)
                        .accessibilityIdentifier("shaders.optimize")
                }
                Button("关闭") { dismiss() }
                    .disabled(refreshing || operation != nil).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 480)
        .interactiveDismissDisabled(refreshing || operation != nil)
        .task { await refresh() }
        .onDisappear { operation?.cancel() }
    }

    private func refresh() async {
        refreshing = true
        readCount = 0
        defer { refreshing = false }
        do {
            let snapshot = try await GameMetalShaderCache.snapshot(prefix: prefix, gameID: gameID, executable: executableName) { value in
                guard value.phase == "scan" else { return }
                Task { @MainActor in if refreshing { readCount = max(readCount, value.processed) } }
            }
            readCount = snapshot.observed
            dxbcCount = 0
            if let gameRoot {
                let observed = readCount
                dxbcCount = try await GameDXBCPrecompile.pendingCount(gameRoot: gameRoot, prefix: prefix, gameID: gameID) { count in
                    Task { @MainActor in if refreshing { readCount = max(readCount, observed + count) } }
                }
                readCount = observed + dxbcCount
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func optimize() {
        guard operation == nil, !refreshing, !gameRunning else { return }
        errorMessage = nil
        progress = GameMetalShaderCache.Progress(processed: 0, total: readCount, failed: 0)
        let workers = workers
        let dxbcCount = dxbcCount
        let readCount = readCount
        let (events, updates) = AsyncStream.makeStream(of: GameMetalShaderCache.Progress.self, bufferingPolicy: .bufferingNewest(1))
        let progressTask = Task {
            var estimate = ShaderOptimizationEstimate()
            for await update in events {
                remaining = estimate.record(update, at: ProcessInfo.processInfo.systemUptime)
                guard update.total > 0, update.isCompilation else { continue }
                let isMetalPass = update.phase == "optimize"
                let priorCount = isMetalPass ? dxbcCount : 0
                progress = GameMetalShaderCache.Progress(processed: priorCount + update.processed,
                    total: isMetalPass ? priorCount + update.total : readCount, failed: update.failed)
            }
        }
        operation = Task {
            defer {
                progress = nil
                remaining = nil
                operation = nil
                library.shaderOptimizationRevision += 1
            }
            do {
                var incomplete = 0
                if let gameRoot, dxbcCount > 0 {
                    let result = try await GameDXBCPrecompile.compile(gameRoot: gameRoot, prefix: prefix, gameID: gameID, workers: workers) { value in
                        updates.yield(.init(processed: value.processed, total: dxbcCount, failed: value.failed, phase: "dxbc"))
                    }
                    incomplete = result.failed + result.unsupported
                    if result.failed == 0 { self.dxbcCount = 0 }
                }
                let snapshot = try await GameMetalShaderCache.optimize(prefix: prefix, gameID: gameID, executable: executableName,
                                                                      workers: workers) { value in
                    updates.yield(value)
                }
                self.readCount = snapshot.observed + self.dxbcCount
                incomplete += snapshot.failed
                if incomplete > 0 { errorMessage = "\(incomplete) 个着色器未完成。" }
            } catch is CancellationError {
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            updates.finish()
            await progressTask.value
        }
    }
}

private extension GameMetalShaderCache.Progress {
    var isCompilation: Bool { phase == "dxbc" || phase == "optimize" }
}

struct ShaderOptimizationEstimate {
    private var sample: (phase: String, time: TimeInterval, processed: Int)?
    private var rate: Double?

    mutating func record(_ progress: GameMetalShaderCache.Progress, at time: TimeInterval) -> Duration? {
        guard let phase = progress.phase, progress.isCompilation, progress.total > 0 else {
            sample = nil
            rate = nil
            return nil
        }
        guard let baseline = sample, baseline.phase == phase, progress.processed >= baseline.processed else {
            sample = (phase, time, progress.processed)
            rate = nil
            return nil
        }
        let change = progress.processed - baseline.processed
        let elapsed = time - baseline.time
        if elapsed >= 1, change > 0 {
            let measured = Double(change) / elapsed
            rate = rate.map { $0 * 0.7 + measured * 0.3 } ?? measured
            sample = (phase, time, progress.processed)
        }
        guard let rate, progress.processed < progress.total else { return nil }
        return .seconds((Double(progress.total - progress.processed) / rate).rounded(.up))
    }
}
