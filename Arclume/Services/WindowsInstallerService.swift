import Foundation

nonisolated enum WindowsInstallerService {
    static func adaptation(for installer: URL) throws -> GameAdaptationRule? {
        guard installer.pathExtension.lowercased() == "exe",
              let rule = GameAdaptationRules.all.first(where: { installer.lastPathComponent.lowercased().hasPrefix($0.installer?.filenamePrefix.lowercased() ?? "\0") }),
              let marker = rule.installer?.signature else { return nil }
        let file = try FileHandle(forReadingFrom: installer)
        defer { try? file.close() }
        let header = try file.read(upToCount: 1_048_576) ?? Data()
        guard header.starts(with: [0x4d, 0x5a]), header.range(of: Data(marker.utf8)) != nil else {
            throw NSError(domain: "Arclume.Adaptation", code: 2, userInfo: [NSLocalizedDescriptionKey: "安装包名称匹配适配规则，但安装器格式未通过验证，未运行。"])
        }
        return rule
    }

    static func arguments(for installer: URL) throws -> [String] {
        let values = try installer.resourceValues(forKeys: [.isRegularFileKey])
        guard installer.isFileURL, values.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let handle = try FileHandle(forReadingFrom: installer)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 8) ?? Data()
        switch installer.pathExtension.lowercased() {
        case "exe" where header.starts(with: [0x4d, 0x5a]):
            if let rule = try adaptation(for: installer) {
                // NSIS /D must be the final unquoted command-line tail. Separate argv
                // words avoid Wine quoting a single argument containing spaces.
                return [installer.path] + ("/D=" + rule.windowsDirectory).components(separatedBy: " ")
            }
            return [installer.path]
        case "msi" where header == Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]):
            return ["msiexec.exe", "/i", "Z:" + installer.path.replacingOccurrences(of: "/", with: "\\")]
        default:
            throw NSError(domain: "Arclume.Installer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "请选择有效的 Windows EXE 或 MSI 安装包。"
            ])
        }
    }

    static func launch(installer: URL, bottle: URL, runtime: ContainerSteamRuntime) throws -> Process {
        let arguments = try arguments(for: installer)
        guard BundledWineRuntime.isValidPrefix(at: bottle) else {
            throw ContainerSteamServiceError.invalidBottle(bottle)
        }
        let wine: URL
        let launchArguments: [String]
        var environment: [String: String]
        switch runtime {
        case .bundledWine:
            guard BundledWineRuntime.ownsPrefix(bottle) || BundledWineRuntime.ownsStandardSteamPrefix(bottle) else {
                throw ContainerSteamServiceError.invalidBottle(bottle)
            }
            let configuration = try BundledWineRuntime.makeDefaultLaunchConfiguration()
            wine = configuration.wineURL
            launchArguments = arguments
            environment = configuration.environment
            environment["WINEPREFIX"] = bottle.path
        case .crossOver:
            throw NSError(domain: "Arclume.Runtime", code: 1,
                userInfo: [NSLocalizedDescriptionKey: BundledRuntimePolicy.retiredMessage])
        }
        OnlineGameBottleConfiguration.applyProcessEnvironment(to: &environment)
        return try FoundationContainerSteamProcessLauncher().launch(.init(
            executableURL: wine, arguments: launchArguments,
            currentDirectoryURL: installer.deletingLastPathComponent(),
            environmentOverrides: environment
        ))
    }
}
