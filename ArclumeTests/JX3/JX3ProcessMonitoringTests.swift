//
//  JX3ProcessMonitoringTests.swift
//  ArclumeTests
//

import Foundation
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
            p809
            n/Users/example/GamesOther/drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/JX3ClientX64.exe
            """,
            rootProcessIdentifier: 808,
            rootProcessIsRunning: true,
            clientLaunchObservedInLog: false,
            requiredBottlePath: "/Users/example/Games"
        )

        #expect(activity.gameProcessIdentifiers.isEmpty)
        #expect(activity.state == .launching)
    }

    @Test @MainActor func directLaunchReusesOnlyTheClientInTheSelectedBottle() {
        let bottle = URL(fileURLWithPath: "/fixture/Games", isDirectory: true)
        let anotherBottle = URL(fileURLWithPath: "/fixture/GamesOther", isDirectory: true)
        func session(_ pid: Int32, executable: String, in bottle: URL) -> OnlineGameLaunchSession {
            OnlineGameLaunchSession(
                processIdentifier: pid,
                executableName: executable,
                logURL: nil,
                bottleURL: bottle,
                runtime: .bundledWine,
                crossOverAppPath: nil,
                closeLauncherWhenGameStarts: false
            )
        }

        let launcher = session(100, executable: "SeasunGame.exe", in: bottle)
        let otherClient = session(101, executable: "JX3ClientX64.exe", in: anotherBottle)
        let client = session(102, executable: "jx3clientx64.exe", in: bottle)

        #expect(OnlineGameLauncher.reusableJX3LaunchSession(
            from: [otherClient, launcher], in: bottle, requiresClient: false
        )?.processIdentifier == 100)
        #expect(OnlineGameLauncher.reusableJX3LaunchSession(
            from: [launcher, otherClient], in: bottle, requiresClient: true
        ) == nil)
        #expect(OnlineGameLauncher.reusableJX3LaunchSession(
            from: [launcher, otherClient, client], in: bottle, requiresClient: true
        )?.processIdentifier == 102)
        #expect(OnlineGameLauncher.reusableJX3LaunchSession(
            from: [launcher, otherClient, client], in: bottle, requiresClient: false
        )?.processIdentifier == 102)
    }

    @Test @MainActor func closeLauncherPreferenceRoundTripsWithGameOptions() {
        let options = GameOptions(closeLauncherWhenGameStarts: true)
        let stored = GameOptionsData(data: options)
        let restored = GameOptions()
        restored.set(data: stored)

        #expect(restored.closeLauncherWhenGameStarts)
    }
}
