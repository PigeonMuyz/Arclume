import SwiftUI
import UniformTypeIdentifiers

struct WindowsInstallerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var installation: WindowsInstallerStore
    @State private var installer: URL?
    @State private var bottles: [URL] = []
    @State private var selectedBottle = ""
    @State private var showFilePicker = false
    @State private var error: String?
    @State private var runtime = StandardGameRuntimeKind.selected()
    @State private var adaptation: GameAdaptationRule?
    @State private var confirmPortableUpdate = false
    @State private var applyGreen = true
    private var isArchive: Bool { installer.map(PortableArchiveReader.supports) ?? false }
    private var bottleURL: URL? { selectedBottle.isEmpty ? nil : URL(fileURLWithPath: selectedBottle, isDirectory: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("安装 Windows 程序").font(.title2.bold())
            LabeledContent("安装包") {
                Button(installer?.lastPathComponent ?? "选择安装包或压缩包…") { showFilePicker = true }
                    .lineLimit(1).help(installer?.path ?? "选择本地安装包")
            }
            .disabled(installation.busy)
            LabeledContent("运行时", value: "Arclume Wine")
            Picker("目标容器", selection: $selectedBottle) {
                Text("请选择容器").tag("")
                ForEach(bottles, id: \.path) { Text($0.lastPathComponent).tag($0.path) }
            }
            .disabled(installation.busy)
            if bottles.isEmpty {
                Text("请先在设置 → 运行时中准备容器。").font(.callout).foregroundStyle(.secondary)
            }
            Text("支持 EXE / MSI 和 ZIP / 7z / RAR。仅导入你信任的软件；压缩包内的 BAT 等脚本不会自动执行。")
                .font(.callout).foregroundStyle(.secondary)
            if let package = installation.portablePackage {
                if package.choices.count > 1 {
                    Picker("主程序", selection: $installation.portableChoiceID) {
                        Text("请选择 EXE").tag("")
                        ForEach(package.choices) { choice in
                            Text("\(choice.name) · \(choice.executable)").tag(choice.id)
                        }
                    }.disabled(installation.busy)
                }
                if let preview = installation.portablePreview {
                    Text("\(preview.choice.name) · \(preview.isUpdate ? "替换更新" : "绿色软件导入")").font(.headline)
                    Text("C:\\" + preview.choice.installDirectory.replacingOccurrences(of: "/", with: "\\"))
                        .font(.caption).textSelection(.enabled)
                    Text("请先退出所有 Windows 程序。保留登录数据和注册表；更新后可打开旧版本目录找回本地文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if preview.choice.ruleID == nil {
                        Text("未匹配适配规则：本次作为独立软件导入，自动替换更新需补充 JSON 规则。")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if let id = preview.choice.ruleID, GameAdaptationRules.rule(id: id)?.greenPreparation != nil {
                        Toggle("应用绿色适配（去广告、关闭内置更新）", isOn: $applyGreen).disabled(installation.busy)
                        Text("仅处理审核过的推广目录，旧内容先保留；不运行完整 BAT，不清空登录数据。也可稍后右键软件单独应用。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let adaptation {
                Text("\(adaptation.name) · 规则固定目录").font(.headline)
                Text(adaptation.windowsDirectory).font(.caption).textSelection(.enabled)
                ForEach(GameAdaptationRules.all.filter { $0.launcherID == adaptation.id }, id: \.id) { child in
                    Text("\(child.name)：\(child.windowsDirectory)").font(.caption).textSelection(.enabled)
                }
                Text("将向安装器传入默认目录。第三方安装器仍可能允许更改；Arclume 会拒绝接入或启动偏离规则路径的适配程序，不会自动搬移旧安装。").font(.footnote).foregroundStyle(.orange)
            }
            if installation.busy { ProgressView().controlSize(.small) }
            if let message = installation.message { Text(message).font(.callout) }
            if let recovery = installation.portableRecovery {
                Button("打开旧版本恢复目录") { NSWorkspace.shared.open(recovery) }
            }
            if let recovery = installation.greenRecovery {
                Button("打开绿色适配恢复目录") { NSWorkspace.shared.open(recovery) }
            }
            if !installation.candidates.isEmpty {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(installation.candidates) { candidate in
                            Button { installation.select(candidate) } label: {
                                VStack(alignment: .leading) {
                                    Text(candidate.name)
                                    Text(candidate.executable.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }.buttonStyle(.bordered)
                        }
                    }
                }.frame(maxHeight: 180)
            }
            if let error = error ?? installation.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction).disabled(installation.preparing)
                if installation.busy && !installation.preparing {
                    Button("停止识别") { installation.stopMonitoring() }
                }
                Spacer()
                Button(isArchive ? (installation.portablePreview?.isUpdate == true ? "替换更新…" : "导入软件") : "运行安装包") {
                    if isArchive && installation.portablePreview?.isUpdate == true { confirmPortableUpdate = true }
                    else { launch() }
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(installer == nil || selectedBottle.isEmpty || installation.busy || libraryPageGlobals.isStoppingWine || (isArchive && installation.portablePreview == nil))
            }
        }
        .padding(28).frame(width: 520)
        .interactiveDismissDisabled(installation.preparing)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [
            UTType(filenameExtension: "exe") ?? .data,
            UTType(filenameExtension: "msi") ?? .data,
            UTType(filenameExtension: "zip") ?? .data,
            UTType(filenameExtension: "7z") ?? .data,
            UTType(filenameExtension: "rar") ?? .data
        ]) { result in
            do {
                let url = try result.get()
                if PortableArchiveReader.supports(url) {
                    adaptation = nil
                    installation.preparePortable(url, bottle: bottleURL)
                } else {
                    _ = try WindowsInstallerService.arguments(for: url)
                    adaptation = try WindowsInstallerService.adaptation(for: url)
                    installation.discardPortable()
                }
                installer = url
                error = nil
            } catch { self.error = error.localizedDescription }
        }
        .onAppear { refreshBottles() }
        .onChange(of: runtime) { _, _ in refreshBottles() }
        .onChange(of: selectedBottle) { _, _ in installation.refreshPortablePreview(bottle: bottleURL) }
        .onChange(of: installation.portableChoiceID) { _, _ in installation.refreshPortablePreview(bottle: bottleURL) }
        .onDisappear { installation.discardPortable() }
        .confirmationDialog("替换已有软件？", isPresented: $confirmPortableUpdate) {
            Button("替换更新", role: .destructive) { launch() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("用所选压缩包替换软件本体，保留原启动入口、AppData 和注册表。旧目录会保留供恢复；这不会验证新版是否可登录或使用语音。")
        }
    }

    private func refreshBottles() {
        error = nil
        switch runtime {
        case .bundledWine:
            bottles = [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL]
                .filter { BundledWineRuntime.isValidPrefix(at: $0) }
        case .crossOver:
            do {
                bottles = try appGlobals.cxAppPath.map { try getAllBottles(appDir: URL(fileURLWithPath: $0)) } ?? []
            } catch { bottles = []; self.error = error.localizedDescription }
        }
        let current = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)?.path
        selectedBottle = bottles.first(where: { $0.path == current })?.path ?? bottles.first?.path ?? ""
    }

    private func launch() {
        guard let installer, !selectedBottle.isEmpty else { return }
        let bottle = URL(fileURLWithPath: selectedBottle, isDirectory: true)
        if isArchive {
            installation.installPortable(applyGreen: applyGreen) { candidate in
                libraryPageGlobals.addInstalledProgram(candidate, bottle: bottle,
                    runtimeKind: StandardGameRuntimeKind.bundledWine.rawValue, crossOverPath: nil, userInitiated: true)
            }
            return
        }
        let capturedRuntime: ContainerSteamRuntime
        if runtime == .bundledWine { capturedRuntime = .bundledWine }
        else if let path = appGlobals.cxAppPath { capturedRuntime = .crossOver(URL(fileURLWithPath: path)) }
        else { error = "请先在设置中选择 CrossOver.app。"; return }
        error = nil
        let runtimeKind = runtime.rawValue
        let crossOverPath = appGlobals.cxAppPath
        installation.start(installer: installer, bottle: bottle, runtime: capturedRuntime) { candidate in
            libraryPageGlobals.addInstalledProgram(candidate, bottle: bottle,
                runtimeKind: runtimeKind, crossOverPath: crossOverPath)
        }
    }
}
