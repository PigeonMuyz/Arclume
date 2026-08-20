//
//  ArclumeRuntimeManifest.swift
//  Arclume
//

import Foundation

nonisolated enum ArclumeRuntimeManifestError: LocalizedError {
    case missing
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missing:
            "App 内未找到 Arclume Wine Runtime Manifest。"
        case .invalid(let reason):
            "Arclume Wine Runtime Manifest 无效：\(reason)"
        }
    }
}

/// The App-side contract for a release produced by the private
/// `Arclume-Runtime` repository. Keep this deliberately small: it is enough
/// to install, validate, update and migrate a runtime without coupling the
/// launcher to Wine's source-tree layout.
nonisolated struct ArclumeRuntimeManifest: Codable, Equatable, Sendable {
    nonisolated struct Archive: Codable, Equatable, Sendable {
        let name: String
        let sha256: String
        let rootDirectory: String
    }

    let schemaVersion: Int
    let id: String
    let displayName: String
    let version: String
    let channel: String
    let runtimeABI: Int
    let prefixABI: String
    let architecture: String
    let minimumMacOS: String
    let legacyInstallRoots: [String]
    let legacyInstallMarkers: [String]
    let archive: Archive

    static let resourceName = "arclume-wine-runtime"

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: BundledOnlineGameResources.resourceSubdirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: "json")
        else {
            throw ArclumeRuntimeManifestError.missing
        }

        do {
            let manifest = try JSONDecoder().decode(
                Self.self,
                from: Data(contentsOf: url)
            )
            try manifest.validate()
            return manifest
        } catch let error as ArclumeRuntimeManifestError {
            throw error
        } catch {
            throw ArclumeRuntimeManifestError.invalid(error.localizedDescription)
        }
    }

    func validate() throws {
        guard schemaVersion == 1 else {
            throw ArclumeRuntimeManifestError.invalid("不支持的 schemaVersion \(schemaVersion)")
        }
        guard id == "io.arclume.runtime.wine",
              !displayName.isEmpty,
              !version.isEmpty,
              runtimeABI > 0,
              architecture == "x86_64",
              isSafeFileName(archive.name),
              isSafeFileName(archive.rootDirectory),
              archive.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              legacyInstallRoots.allSatisfy({ isSafeFileName($0) }),
              !legacyInstallMarkers.contains(where: \.isEmpty)
        else {
            throw ArclumeRuntimeManifestError.invalid("运行时标识、归档名或校验信息不符合约定")
        }
    }

    private func isSafeFileName(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("/")
            && !value.contains("\\")
            && value != "."
            && value != ".."
    }
}
