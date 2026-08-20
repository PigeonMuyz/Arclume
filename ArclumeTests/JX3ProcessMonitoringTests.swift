//
//  JX3ProcessMonitoringTests.swift
//  ProcyonTests
//

import Testing

@testable import Arclume

struct JX3ProcessMonitoringTests {
    @Test func identifiesLauncherAndClientFromProcessArguments() {
        let activity = OnlineGameLauncher.classifyJX3Activity(
            processList: """
              410   1 /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine C:\\SeasunGame\\SeasunGame.exe
              411 410 /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine C:\\SeasunGame\\Game\\JX3\\bin\\zhcn_hd\\JX3ClientX64.exe
            """,
            openFiles: "",
            rootProcessIdentifier: 410,
            rootProcessIsRunning: true,
            clientLaunchObservedInLog: false
        )

        #expect(activity.launcherProcessIdentifiers == [410])
        #expect(activity.gameProcessIdentifiers == [411])
        #expect(activity.state == .gameRunning)
    }

    @Test func identifiesWinePreloadersFromOpenExecutables() {
        let activity = OnlineGameLauncher.classifyJX3Activity(
            processList: """
              501   1 wine64-preloader
              502   1 wine64-preloader
            """,
            openFiles: """
            p501
            n/Users/example/Games/drive_c/SeasunGame/SeasunGame.exe
            p502
            n/Users/example/Games/drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/JX3ClientX64.exe
            """,
            rootProcessIdentifier: 501,
            rootProcessIsRunning: true,
            clientLaunchObservedInLog: false
        )

        #expect(activity.launcherProcessIdentifiers == [501])
        #expect(activity.gameProcessIdentifiers == [502])
        #expect(activity.state == .gameRunning)
    }

    @Test func launcherLogSignalPromotesActivityUntilProcessScanCatchesUp() {
        let log = """
        [XCommon] DetachProgram(C:/SeasunGame/Game/JX3/bin/zhcn_hd/JX3ClientX64.exe) Success
        """
        #expect(OnlineGameLauncher.containsClientLaunchSignal(in: log))

        let activity = OnlineGameLauncher.classifyJX3Activity(
            processList: "",
            openFiles: "",
            rootProcessIdentifier: 700,
            rootProcessIsRunning: true,
            clientLaunchObservedInLog: true
        )
        #expect(activity.state == .gameRunning)
    }

    @Test func processSignalsAreConfinedToTheSelectedGamesPrefix() {
        let activity = OnlineGameLauncher.classifyJX3Activity(
            processList: "",
            openFiles: """
            p808
            n/Users/example/OtherBottle/drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/JX3ClientX64.exe
            """,
            rootProcessIdentifier: 808,
            rootProcessIsRunning: true,
            clientLaunchObservedInLog: false,
            requiredBottlePath: "/Users/example/Games"
        )

        #expect(activity.gameProcessIdentifiers.isEmpty)
        #expect(activity.state == .launching)
    }

    @Test @MainActor func closeLauncherPreferenceRoundTripsWithGameOptions() {
        let options = GameOptions(closeLauncherWhenGameStarts: true)
        let stored = GameOptionsData(data: options)
        let restored = GameOptions()
        restored.set(data: stored)

        #expect(restored.closeLauncherWhenGameStarts)
    }
}
