import Foundation

/// Debug-only isolation. Release builds ignore all test launch overrides.
nonisolated enum ArclumeTestEnvironment {
    static var isUIFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_FIXTURE"] == "1"
        #else
        false
        #endif
    }
    static var isTesting: Bool {
        #if DEBUG
        isUIFixture || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }
    static let defaultsSuite: String = {
        let supplied = ProcessInfo.processInfo.environment["ARCLUME_TEST_RUN_ID"].flatMap(UUID.init(uuidString:))
        return "io.github.pigeonmuyz.arclume.tests." + (supplied ?? UUID()).uuidString
    }()

    @MainActor static func nativeSteamStore() -> NativeSteamStore {
        #if DEBUG
        if isUIFixture { return NativeSteamStore(launcher: FixtureSteamLauncher()) }
        #endif
        return NativeSteamStore()
    }
}

#if DEBUG
@MainActor private final class FixtureSteamLauncher: NativeSteamLaunching {
    var applicationURL: URL? { URL(fileURLWithPath: "/Arclume-UI-Fixture/Steam.app") }
    func install(appID: Int) throws { throw CocoaError(.featureUnsupported) }
}
#endif
