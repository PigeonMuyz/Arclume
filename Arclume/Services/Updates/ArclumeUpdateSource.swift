//
//  ArclumeUpdateSource.swift
//  Arclume
//

import Foundation

nonisolated enum ArclumeUpdateMirrorMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case official
    case builtInMirror
    case customMirror

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动"
        case .official: "GitHub 官方"
        case .builtInMirror: "内置镜像"
        case .customMirror: "自定义镜像"
        }
    }
}

nonisolated enum ArclumeUpdatePreferences {
    static let automaticallyCheck = "arclume.update.automaticallyCheck.v1"
    static let checkAtEveryLaunch = "arclume.update.checkAtEveryLaunch.v1"
    static let mirrorMode = "arclume.update.mirrorMode.v1"
    static let customMirrorPrefix = "arclume.update.customMirrorPrefix.v1"
    static let lastWorkingMirrorPrefix = "arclume.update.lastWorkingMirrorPrefix.v1"
    static let applicationLastCheckedAt = "arclume.update.application.lastCheckedAt.v1"
    static let runtimeLastCheckedAt = "arclume.update.runtime.lastCheckedAt.v1"

    static func prepareDefaults(in defaults: UserDefaults) {
        defaults.register(defaults: [
            automaticallyCheck: true,
            checkAtEveryLaunch: false,
            mirrorMode: ArclumeUpdateMirrorMode.automatic.rawValue,
            customMirrorPrefix: "",
        ])
    }
}

nonisolated struct ArclumeUpdateSourceCandidate: Equatable, Sendable {
    enum Kind: String, Sendable {
        case official
        case builtInMirror
        case customMirror
    }

    let url: URL
    let kind: Kind
    let mirrorPrefix: String?
}

/// Resolves an official GitHub URL through a user-selected transport mirror.
/// Mirrors are URL prefixes: a prefix such as `https://mirror.example/` is
/// followed by the original GitHub URL. This supports both generic GitHub
/// proxies and an owner-operated update gateway without changing metadata.
nonisolated enum ArclumeUpdateSource {
    static let builtInMirrorPrefix = "https://gh-proxy.com/"

    static func selectedMode(in defaults: UserDefaults? = nil) -> ArclumeUpdateMirrorMode {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName)
        return ArclumeUpdateMirrorMode(
            rawValue: defaults?.string(forKey: ArclumeUpdatePreferences.mirrorMode) ?? ""
        ) ?? .automatic
    }

    static func candidates(
        for officialURL: URL,
        in defaults: UserDefaults? = nil
    ) -> [ArclumeUpdateSourceCandidate] {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName)
        let mode = selectedMode(in: defaults)
        let customPrefix = normalizedPrefix(
            defaults?.string(forKey: ArclumeUpdatePreferences.customMirrorPrefix)
        )
        let rememberedPrefix = normalizedPrefix(
            defaults?.string(forKey: ArclumeUpdatePreferences.lastWorkingMirrorPrefix)
        )

        var result: [ArclumeUpdateSourceCandidate] = []
        func appendMirror(_ prefix: String?, kind: ArclumeUpdateSourceCandidate.Kind) {
            guard let prefix,
                  let url = URL(string: prefix + officialURL.absoluteString)
            else { return }
            result.append(.init(url: url, kind: kind, mirrorPrefix: prefix))
        }
        func appendOfficial() {
            result.append(.init(url: officialURL, kind: .official, mirrorPrefix: nil))
        }

        switch mode {
        case .automatic:
            if rememberedPrefix == customPrefix {
                appendMirror(rememberedPrefix, kind: .customMirror)
            } else if rememberedPrefix == builtInMirrorPrefix {
                appendMirror(rememberedPrefix, kind: .builtInMirror)
            }
            appendMirror(customPrefix, kind: .customMirror)
            appendMirror(builtInMirrorPrefix, kind: .builtInMirror)
            appendOfficial()
        case .official:
            appendOfficial()
        case .builtInMirror:
            appendMirror(builtInMirrorPrefix, kind: .builtInMirror)
            appendOfficial()
        case .customMirror:
            appendMirror(customPrefix, kind: .customMirror)
            appendOfficial()
        }

        var seen = Set<String>()
        return result.filter { seen.insert($0.url.absoluteString).inserted }
    }

    static func rememberSuccessfulCandidate(
        _ candidate: ArclumeUpdateSourceCandidate,
        in defaults: UserDefaults? = nil
    ) {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName)
        if let prefix = candidate.mirrorPrefix {
            defaults?.set(
                prefix,
                forKey: ArclumeUpdatePreferences.lastWorkingMirrorPrefix
            )
        } else {
            defaults?.removeObject(
                forKey: ArclumeUpdatePreferences.lastWorkingMirrorPrefix
            )
        }
    }

    static func normalizedPrefix(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false
        else {
            return nil
        }
        return value.hasSuffix("/") ? value : value + "/"
    }
}
