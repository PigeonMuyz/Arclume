import Foundation
import Combine

@MainActor
final class WindowsInstallerStore: ObservableObject {
    @Published var busy = false
    @Published var preparing = false
    @Published var message: String?
    @Published var error: String?
    @Published var candidates: [InstalledProgramCandidate] = []
    @Published var portablePackage: PortablePackage?
    @Published var portableChoiceID = ""
    @Published var portablePreview: PortableInstallPreview?
    @Published var portableRecovery: URL?
    @Published var greenRecovery: URL?
    private var monitor: Task<Void, Never>?
    private var addCandidate: ((InstalledProgramCandidate) -> Void)?
    private var targetBottle: URL?

    func discardPortable() {
        guard !busy else { return }
        if let staging = portablePackage?.staging { try? FileManager.default.removeItem(at: staging) }
        portablePackage = nil; portablePreview = nil; portableChoiceID = ""
    }

    func preparePortable(_ archive: URL, bottle: URL?) {
        guard !busy else { return }
        discardPortable()
        busy = true; preparing = true; error = nil; candidates = []; portableRecovery = nil; greenRecovery = nil
        message = "正在安全解压和识别主程序，不执行任何脚本…"
        monitor = Task {
            defer { busy = false; preparing = false; monitor = nil }
            do {
                let package = try await Task.detached(priority: .userInitiated) { try PortableSoftwareService.prepare(archive) }.value
                portablePackage = package
                portableChoiceID = package.choices.count == 1 ? package.choices[0].id : ""
                refreshPortablePreview(bottle: bottle)
                message = package.choices.count == 1 ? "压缩包已就绪，确认后导入；不会自动启动软件。" : "请选择主程序；未适配的软件会保留完整包内目录。"
            } catch { self.error = error.localizedDescription; message = nil }
        }
    }

    func refreshPortablePreview(bottle: URL?) {
        portablePreview = nil
        guard let bottle, let choice = portablePackage?.choices.first(where: { $0.id == portableChoiceID }) else { return }
        do {
            portablePreview = try PortableSoftwareService.preview(choice, bottle: bottle,
                ownedBottles: [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL])
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func installPortable(applyGreen: Bool = false, add: @escaping (InstalledProgramCandidate) -> Void) {
        guard !busy, let preview = portablePreview else { return }
        busy = true; preparing = true; error = nil
        message = preview.isUpdate ? "正在替换更新，保留旧版本供恢复…" : "正在导入绿色软件…"
        monitor = Task {
            defer { busy = false; preparing = false; monitor = nil }
            do {
                let (result, green) = try await Task.detached(priority: .userInitiated) {
                    guard BundledWineRuntime.isValidPrefix(at: preview.bottle) else { throw BundledWineRuntimeError.invalidPrefix }
                    let installed = try PortableSoftwareService.install(preview,
                        ownedBottles: [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL])
                    var green: PortableGreenPreparation.Result?
                    if applyGreen, GameAdaptationRules.matching(installed.0.executable)?.greenPreparation != nil {
                        do {
                            let owned = [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL]
                            let plan = try PortableGreenPreparation.plan(executable: installed.0.executable, bottle: preview.bottle, ownedBottles: owned)
                            green = PortableGreenPreparation.apply(plan, ownedBottles: owned)
                        } catch { green = .init(error: error.localizedDescription) }
                    }
                    return (installed, green)
                }.value
                add(result.0)
                portableRecovery = result.1
                greenRecovery = green?.recovery
                message = preview.isUpdate ? "已替换更新：\(result.0.name)。原启动入口不变，旧版本已保留。" : "已导入：\(result.0.name)。可从库中启动，BAT 等脚本未执行。"
                if let green {
                    if let failure = green.error { self.error = "软件导入成功，但绿色适配未全部完成：\(failure)" }
                    else { message = (message ?? "") + " 已应用绿色适配。" }
                }
                if let staging = portablePackage?.staging { try? FileManager.default.removeItem(at: staging) }
                portablePackage = nil; portablePreview = nil; portableChoiceID = ""
            } catch { self.error = error.localizedDescription; message = nil }
        }
    }

    func start(installer: URL, bottle: URL, runtime: ContainerSteamRuntime,
               add: @escaping (InstalledProgramCandidate) -> Void) {
        guard !busy else { return }
        busy = true; preparing = true; error = nil; candidates = []
        message = "正在准备安装程序…"
        addCandidate = add
        targetBottle = bottle
        monitor = Task {
            defer { busy = false; preparing = false; monitor = nil }
            do {
                let before = await Task.detached(priority: .utility) { InstalledProgramDiscovery.scan(bottle: bottle) }.value
                try Task.checkCancellation()
                let process = try await Task.detached(priority: .userInitiated) {
                    try WindowsInstallerService.launch(installer: installer, bottle: bottle, runtime: runtime)
                }.value
                preparing = false
                message = "安装中，将自动识别新程序。可以关闭此窗口。"
                let deadline = ContinuousClock.now.advanced(by: .seconds(1800))
                var last: [InstalledProgramCandidate] = []
                var stable = 0
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: .seconds(5))
                    let current = await Task.detached(priority: .utility) { InstalledProgramDiscovery.scan(bottle: bottle) }.value
                    try Task.checkCancellation()
                    let found = InstalledProgramDiscovery.added(after: before, current: current)
                    let rejected = found.filter { (try? GameAdaptationRules.validate($0.executable, bottle: bottle)) == nil }
                    if let invalid = rejected.first {
                        do { try GameAdaptationRules.validate(invalid.executable, bottle: bottle) }
                        catch { self.error = error.localizedDescription }
                    }
                    let accepted = found.filter { !rejected.contains($0) }
                    stable = found == last ? stable + 1 : 0
                    last = found
                    // Installer bootstrap processes can exit before their children;
                    // also require the new entry and its target to settle for 20s.
                    if !process.isRunning, !found.isEmpty, stable >= 4 {
                        if process.terminationReason == .exit, process.terminationStatus != 0 {
                            candidates = accepted
                            message = "安装程序返回状态 \(process.terminationStatus)，请确认要添加的入口。"
                        } else if accepted.count == 1, accepted[0].isShortcut {
                            add(accepted[0])
                            message = "已自动添加：\(accepted[0].name)"
                        } else {
                            candidates = accepted
                            message = "发现新程序，请选择启动入口。"
                        }
                        return
                    }
                }
                candidates = last.filter { (try? GameAdaptationRules.validate($0.executable, bottle: bottle)) != nil }
                message = "自动识别已结束。未找到明确入口时，可手动添加已安装程序。"
            } catch is CancellationError {
                message = "已停止自动识别；不会结束安装程序。"
            } catch { self.error = error.localizedDescription; message = nil }
        }
    }

    func select(_ candidate: InstalledProgramCandidate) {
        guard !busy, candidates.contains(candidate) else { return }
        guard let targetBottle else { return }
        do { try GameAdaptationRules.validate(candidate.executable, bottle: targetBottle) }
        catch { self.error = error.localizedDescription; return }
        addCandidate?(candidate)
        candidates = []
        message = "已添加：\(candidate.name)"
    }

    func stopMonitoring() { monitor?.cancel() }
}
