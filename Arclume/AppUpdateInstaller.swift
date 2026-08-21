//
//  AppUpdateInstaller.swift
//  Arclume
//

import Foundation
import Security

nonisolated enum ArclumeAppUpdateInstallationResult: Sendable {
    case installed(URL)
}

nonisolated enum ArclumeAppUpdateInstallationError: LocalizedError {
    case cannotMount
    case appMissing
    case invalidIdentityOrVersion
    case invalidSignature
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotMount:
            "无法挂载更新磁盘映像。"
        case .appMissing:
            "更新磁盘映像中未找到 Arclume.app。"
        case .invalidIdentityOrVersion:
            "更新 App 的标识或版本不正确。"
        case .invalidSignature:
            "更新 App 未通过 Arclume 开发者签名验证。"
        case .installationFailed(let message):
            "无法自动安装更新：\(message)"
        }
    }
}

/// Fankit-style in-place updater. The update image is mounted read-only, and
/// the contained application must satisfy the current application's exact
/// bundle identifier and signing-team requirement before any replacement.
nonisolated enum ArclumeAppUpdateInstaller {
    static func install(
        diskImageURL: URL,
        releaseVersion: String,
        releaseBuild: String?,
        currentVersion: String,
        currentBuild: String,
        currentAppURL: URL
    ) throws -> ArclumeAppUpdateInstallationResult {
        let currentAppURL = currentAppURL.standardizedFileURL.resolvingSymlinksInPath()
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.pigeonmuyz.arclume"
        guard let teamIdentifier = ArclumeAppCodeSigning.teamIdentifier() else {
            throw ArclumeAppUpdateInstallationError.invalidSignature
        }
        let requirement = ArclumeAppCodeSigning.requirement(
            identifier: bundleIdentifier,
            teamIdentifier: teamIdentifier
        )

        let mountPoint = try mount(diskImageURL)
        defer { try? eject(mountPoint) }
        let updateAppURL = mountPoint.appendingPathComponent("Arclume.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: updateAppURL.path) else {
            throw ArclumeAppUpdateInstallationError.appMissing
        }
        try validate(
            appAt: updateAppURL,
            releaseVersion: releaseVersion,
            releaseBuild: releaseBuild,
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            bundleIdentifier: bundleIdentifier,
            codeSigningRequirement: requirement
        )

        let parentURL = currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentURL.path) else {
            try replaceUsingAdministratorPrivileges(
                updateAppURL: updateAppURL,
                currentAppURL: currentAppURL
            )
            return .installed(currentAppURL)
        }

        try replace(
            updateAppURL: updateAppURL,
            currentAppURL: currentAppURL,
            releaseVersion: releaseVersion,
            releaseBuild: releaseBuild,
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            bundleIdentifier: bundleIdentifier,
            codeSigningRequirement: requirement
        )
        return .installed(currentAppURL)
    }

    private static func replace(
        updateAppURL: URL,
        currentAppURL: URL,
        releaseVersion: String,
        releaseBuild: String?,
        currentVersion: String,
        currentBuild: String,
        bundleIdentifier: String,
        codeSigningRequirement: String
    ) throws {
        let fileManager = FileManager.default
        let parentURL = currentAppURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".Arclume-update-\(UUID().uuidString).app",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingURL) }

        do {
            try fileManager.copyItem(at: updateAppURL, to: stagingURL)
            try validate(
                appAt: stagingURL,
                releaseVersion: releaseVersion,
                releaseBuild: releaseBuild,
                currentVersion: currentVersion,
                currentBuild: currentBuild,
                bundleIdentifier: bundleIdentifier,
                codeSigningRequirement: codeSigningRequirement
            )
            _ = try fileManager.replaceItemAt(currentAppURL, withItemAt: stagingURL)
        } catch let error as ArclumeAppUpdateInstallationError {
            throw error
        } catch {
            throw ArclumeAppUpdateInstallationError.installationFailed(error.localizedDescription)
        }
    }

    /// Arclume does not install a persistent privileged service. For an app
    /// located in /Applications this asks macOS once for administrator access
    /// and performs the same staged replacement while the already-validated,
    /// read-only update image remains mounted.
    private static func replaceUsingAdministratorPrivileges(
        updateAppURL: URL,
        currentAppURL: URL
    ) throws {
        let parentURL = currentAppURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".Arclume-update-\(UUID().uuidString).app",
            isDirectory: true
        )
        let backupURL = parentURL.appendingPathComponent(
            ".Arclume-previous-\(UUID().uuidString).app",
            isDirectory: true
        )

        let command = [
            "set -eu",
            "stage=\(shellQuote(stagingURL.path))",
            "backup=\(shellQuote(backupURL.path))",
            "target=\(shellQuote(currentAppURL.path))",
            "source=\(shellQuote(updateAppURL.path))",
            "owner=$(/usr/sbin/stat -f '%u:%g' \"$target\")",
            "rollback() { if [ -e \"$backup\" ] && [ ! -e \"$target\" ]; then /bin/mv \"$backup\" \"$target\"; fi; }",
            "trap rollback EXIT",
            "/usr/bin/ditto \"$source\" \"$stage\"",
            "/usr/sbin/chown -R \"$owner\" \"$stage\"",
            "/bin/mv \"$target\" \"$backup\"",
            "/bin/mv \"$stage\" \"$target\"",
            "/bin/rm -rf \"$backup\"",
            "trap - EXIT",
        ].joined(separator: "; ")
        let appleScript = "do shell script \(appleScriptString(command)) with administrator privileges"
        _ = try run("/usr/bin/osascript", arguments: ["-e", appleScript])
    }

    private static func mount(_ diskImageURL: URL) throws -> URL {
        let data = try run(
            "/usr/sbin/diskutil",
            arguments: [
                "image", "attach", "--mountOptions", "nobrowse", "--readOnly", "--plist",
                diskImageURL.path,
            ]
        )
        guard let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
            let entities = propertyList["system-entities"] as? [[String: Any]],
            let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw ArclumeAppUpdateInstallationError.cannotMount
        }
        return URL(fileURLWithPath: mountPath, isDirectory: true)
    }

    private static func eject(_ mountPoint: URL) throws {
        _ = try run("/usr/sbin/diskutil", arguments: ["eject", mountPoint.path])
    }

    private static func validate(
        appAt appURL: URL,
        releaseVersion: String,
        releaseBuild: String?,
        currentVersion: String,
        currentBuild: String,
        bundleIdentifier: String,
        codeSigningRequirement: String
    ) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String,
              version == releaseVersion
        else {
            throw ArclumeAppUpdateInstallationError.invalidIdentityOrVersion
        }
        if let releaseBuild,
           info["CFBundleVersion"] as? String != releaseBuild
        {
            throw ArclumeAppUpdateInstallationError.invalidIdentityOrVersion
        }
        let versionComparison = version.compare(
            currentVersion,
            options: [.numeric, .caseInsensitive]
        )
        let isNewer = versionComparison == .orderedDescending
            || (versionComparison == .orderedSame
                && (releaseBuild.flatMap(Int.init) ?? 0) > (Int(currentBuild) ?? 0))
        guard isNewer else {
            throw ArclumeAppUpdateInstallationError.invalidIdentityOrVersion
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw ArclumeAppUpdateInstallationError.invalidSignature
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            codeSigningRequirement as CFString,
            [],
            &requirement
        ) == errSecSuccess,
            let requirement
        else {
            throw ArclumeAppUpdateInstallationError.invalidSignature
        }
        let flags = SecCSFlags(rawValue:
            UInt32(kSecCSStrictValidate)
                | UInt32(kSecCSCheckAllArchitectures)
                | UInt32(kSecCSCheckNestedCode)
        )
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw ArclumeAppUpdateInstallationError.invalidSignature
        }
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw ArclumeAppUpdateInstallationError.installationFailed(message)
        }
        return output
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

nonisolated enum ArclumeAppCodeSigning {
    static func teamIdentifier() -> String? {
        var code: SecCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code {
            var staticCode: SecStaticCode?
            if SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
               let staticCode
            {
                var information: CFDictionary?
                let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
                if SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
                   let dictionary = information as? [CFString: Any],
                   let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier] as? String
                {
                    return teamIdentifier
                }
            }
        }
        return nil
    }

    static func requirement(identifier: String, teamIdentifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}
