//
//  OnlineGameTests.swift
//  ProcyonTests
//

import Foundation
import CoreFoundation
import Testing

@testable import Procyon

struct OnlineGameTests {
    @Test func onlineModeUsesGamesAsItsDefaultBottleName() {
        #expect(OnlineGameMode.defaultBottleName == "Games")
    }

    @Test func onlineGameOptionsExposeD3DMetal3AndD3DMetal4() {
        #expect(OnlineGameMode.onlineGraphicsBackends.map(\.id) == ["d3dmetal3", "d3dmetal4"])
        #expect(OnlineGameMode.onlineGraphicsBackends.map(\.label) == ["D3DMetal 3", "D3DMetal 4 Beta 2"])
        #expect(OnlineGameMode.defaultGraphicsBackend == "d3dmetal4")
        #expect(GameOptions().wineMSync)
        #expect(!GameOptions().dlssFrameGenerationEnabled)
    }

    @Test func savedDLSSFrameGenerationPreferenceIsRestored() throws {
        let data = try JSONDecoder().decode(
            GameOptionsData.self,
            from: Data(#"{"dlssFrameGenerationEnabled":true}"#.utf8)
        )
        let options = GameOptions()

        options.set(data: data)

        #expect(options.dlssFrameGenerationEnabled)
    }

    @Test @MainActor func onlineGamePresentationRoundTripPreservesLogo() throws {
        let artwork = OnlineGameArtwork(
            id: UUID(),
            urlString: "file:///tmp/jx3-poster.png"
        )
        let presentation = OnlineGamePresentation(
            title: "剑网3启动器",
            artworks: [artwork],
            selectedArtworkID: artwork.id,
            logoURLString: "file:///tmp/jx3-logo.png"
        )

        let data = try JSONEncoder().encode(presentation)
        let decoded = try JSONDecoder().decode(OnlineGamePresentation.self, from: data)

        #expect(decoded == presentation)
    }

    @Test func jx3LauncherFeedDecodesOfficialResponsesAndBuildsNoticeLinks() throws {
        let carouselData = Data(#"""
        {
            "code": 1,
            "data": {
                "list": [
                    {
                        "id": 358401,
                        "title": "剑网3官方活动",
                        "thumb": "https://jx3.xoyo.com/uploadfile/banner.jpg",
                        "url": "https://jx3.xoyo.com/article/358401",
                        "description": "官方活动介绍",
                        "inputtime": 1760000000
                    },
                    {
                        "id": "358402",
                        "title": "无图片内容",
                        "thumb": ""
                    }
                ]
            }
        }
        """#.utf8)
        let newsData = Data(#"{"code":1,"data":{"list":[]}}"#.utf8)
        let activitiesData = Data(#"{"code":1,"data":{"list":[]}}"#.utf8)
        let noticesData = Data(#"""
        {
            "code": 1,
            "data": {
                "list": [
                    {
                        "id": 20260730,
                        "title": "版本更新公告",
                        "url": 20260730,
                        "asktime": "2026-07-30"
                    }
                ]
            }
        }
        """#.utf8)
        let recommendationsData = Data(#"""
        {
            "tj_latest_title": "最新版本",
            "tj_latest_href": "https://jx3.xoyo.com/latest",
            "tj_news_title": "新闻",
            "tj_news_href": "https://jx3.xoyo.com/news"
        }
        """#.utf8)

        let feed = try JX3LauncherFeedStore.makeFeed(
            carouselData: carouselData,
            newsData: newsData,
            activitiesData: activitiesData,
            noticesData: noticesData,
            recommendationsData: recommendationsData,
            fetchedAt: Date(timeIntervalSince1970: 1760000000)
        )

        #expect(feed.carousel.count == 2)
        #expect(feed.carousel[0].id == "358401")
        #expect(feed.carousel[0].thumbnailURL?.absoluteString == "https://jx3.xoyo.com/uploadfile/banner.jpg")
        #expect(feed.carousel[1].thumbnailURL == nil)
        #expect(feed.primaryArtworkURL?.absoluteString == "https://jx3.xoyo.com/uploadfile/banner.jpg")
        #expect(feed.notices.first?.id == "20260730")
        #expect(feed.notices.first?.detailURL?.absoluteString == "https://jx3.xoyo.com/announce/gg.html?id=20260730")
        #expect(feed.recommendations?.latestTitle == "最新版本")
    }

    @Test func downloadScannerFindsNamedLauncherFolderAndZip() throws {
        let downloads = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: downloads) }

        try FileManager.default.createDirectory(
            at: downloads.appendingPathComponent("SeasunGame", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: downloads.appendingPathComponent("SeasunGame.zip").path,
            contents: Data()
        )
        FileManager.default.createFile(
            atPath: downloads.appendingPathComponent("other.zip").path,
            contents: Data()
        )

        let candidates = OnlineLauncherDownloadScanner.candidates(in: downloads)

        #expect(candidates.map(\.lastPathComponent) == ["SeasunGame", "SeasunGame.zip"])
    }

    @Test func discoversLauncherAndClientAndPrefersLauncherLaunch() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let gameRoot = bottle.appendingPathComponent("drive_c/SeasunGame/Game/JX3/bin/zhcn_hd")
        try FileManager.default.createDirectory(at: gameRoot, withIntermediateDirectories: true)
        let client = gameRoot.appendingPathComponent(OnlineGameMode.jx3ClientName)
        let launcher = bottle.appendingPathComponent("drive_c/SeasunGame/SeasunGame.exe")
        FileManager.default.createFile(atPath: client.path, contents: Data())
        FileManager.default.createFile(atPath: launcher.path, contents: Data())

        let installation = OnlineGameDiscovery.jx3Installation(in: bottle)

        #expect(installation.clientURL?.standardizedFileURL == client.standardizedFileURL)
        #expect(installation.launcherURL?.standardizedFileURL == launcher.standardizedFileURL)
        #expect(installation.preferredLaunchURL?.standardizedFileURL == launcher.standardizedFileURL)
        #expect(installation.preferredLaunchArguments.isEmpty)
        #expect(OnlineGameDiscovery.games(in: bottle).map(\.id) == [OnlineGameMode.jx3GameID])
    }

    @Test func prefersNewestCompleteLauncherCEFWorkingDirectory() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }

        let launcherRoot = bottle.appendingPathComponent("drive_c/SeasunGame", isDirectory: true)
        let gameRoot = bottle.appendingPathComponent("drive_c/SeasunGame/Game/JX3/bin/zhcn_hd")
        try FileManager.default.createDirectory(at: gameRoot, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: gameRoot.appendingPathComponent(OnlineGameMode.jx3ClientName).path,
            contents: Data()
        )
        FileManager.default.createFile(
            atPath: launcherRoot.appendingPathComponent(OnlineGameMode.jx3LauncherName).path,
            contents: Data()
        )

        for version in ["2.0.0.498", "2.0.0.525"] {
            let versionURL = launcherRoot.appendingPathComponent(
                "SeasunGame_\(version)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: versionURL.appendingPathComponent("CefViewWing.exe").path,
                contents: Data()
            )
            FileManager.default.createFile(
                atPath: versionURL.appendingPathComponent("libcef.dll").path,
                contents: Data()
            )
        }

        let installation = OnlineGameDiscovery.jx3Installation(in: bottle)

        #expect(
            installation.preferredWorkingDirectory?.lastPathComponent == "SeasunGame_2.0.0.525"
        )
    }

    @Test func launcherOnlyInstallationUsesLauncherWithoutDirectArgument() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let launcher = bottle.appendingPathComponent("drive_c/SeasunGame/SeasunGame.exe")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: launcher.path, contents: Data())

        let installation = OnlineGameDiscovery.jx3Installation(in: bottle)

        #expect(installation.clientURL == nil)
        #expect(installation.preferredLaunchURL?.standardizedFileURL == launcher.standardizedFileURL)
        #expect(installation.preferredLaunchArguments.isEmpty)
    }

    @Test func clientOnlyInstallationIsNotDisplayedOrLaunchable() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let client = bottle.appendingPathComponent("drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/JX3ClientX64.exe")
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: client.path, contents: Data())

        let installation = OnlineGameDiscovery.jx3Installation(in: bottle)

        #expect(installation.clientURL?.standardizedFileURL == client.standardizedFileURL)
        #expect(installation.launcherURL == nil)
        #expect(!installation.isDetected)
        #expect(installation.preferredLaunchURL == nil)
        #expect(OnlineGameDiscovery.games(in: bottle).isEmpty)
    }

    @Test func zipLauncherImportFindsTheSingleLauncher() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let payload = workspace.appendingPathComponent("payload/launcher", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let originalLauncher = payload.appendingPathComponent(OnlineGameMode.jx3LauncherName)
        FileManager.default.createFile(atPath: originalLauncher.path, contents: Data())
        let archive = workspace.appendingPathComponent("launcher.zip")
        try run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", workspace.appendingPathComponent("payload").path, archive.path])

        let importedLauncher = try OnlineLauncherImporter.prepareLauncher(from: archive)
        defer { try? FileManager.default.removeItem(at: importedLauncher.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }

        #expect(importedLauncher.lastPathComponent == OnlineGameMode.jx3LauncherName)
        #expect(FileManager.default.fileExists(atPath: importedLauncher.path))
    }

    @Test func folderLauncherImportFindsTheSingleLauncher() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let launcherFolder = workspace.appendingPathComponent("SeasunGame", isDirectory: true)
        try FileManager.default.createDirectory(at: launcherFolder, withIntermediateDirectories: true)
        let launcher = launcherFolder.appendingPathComponent(OnlineGameMode.jx3LauncherName)
        FileManager.default.createFile(atPath: launcher.path, contents: Data())

        let importedLauncher = try OnlineLauncherImporter.prepareLauncher(from: launcherFolder)

        #expect(importedLauncher.standardizedFileURL == launcher.standardizedFileURL)
    }

    @Test func folderImportInstallsLauncherInManagedBottleAndCreatesCard() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let bottle = workspace.appendingPathComponent("Bottle", isDirectory: true)
        let launcherFolder = workspace.appendingPathComponent("Source", isDirectory: true)
        let launcher = launcherFolder.appendingPathComponent(OnlineGameMode.jx3LauncherName)
        let companionFile = launcherFolder.appendingPathComponent("user_settings.ini")
        try FileManager.default.createDirectory(
            at: launcherFolder,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bottle.appendingPathComponent("drive_c", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: launcher.path, contents: Data())
        try "language=zh_CN".write(
            to: companionFile,
            atomically: true,
            encoding: .utf8
        )

        let installedLauncher = try OnlineLauncherImporter.installLauncher(
            from: launcherFolder,
            into: bottle
        )
        let installedCompanion = installedLauncher.deletingLastPathComponent()
            .appendingPathComponent(companionFile.lastPathComponent)
        let games = OnlineGameDiscovery.games(in: bottle)

        #expect(installedLauncher.path.hasPrefix(bottle.path + "/"))
        #expect(
            installedLauncher.standardizedFileURL.path.hasPrefix(
                bottle.appendingPathComponent("drive_c/SeasunGame", isDirectory: true)
                    .standardizedFileURL.path + "/"
            )
        )
        #expect(
            !installedLauncher.standardizedFileURL.path.contains(
                "/drive_c/Program Files/Procyon/JX3Launcher/"
            )
        )
        #expect(FileManager.default.fileExists(atPath: installedLauncher.path))
        #expect(FileManager.default.fileExists(atPath: installedCompanion.path))
        #expect(!FileManager.default.fileExists(atPath: launcherFolder.path))
        #expect(games.count == 1)
        #expect(games.first?.name == "剑网 3 启动器")
        #expect(games.first?.appExeURL?.standardizedFileURL == installedLauncher.standardizedFileURL)
    }

    @Test func runtimeMigrationMovesJX3AndPreservesSourceContainer() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceBottle = workspace.appendingPathComponent("CrossOverGames", isDirectory: true)
        let destinationBottle = workspace.appendingPathComponent("BundledWineGames", isDirectory: true)
        let sourceRoot = sourceBottle.appendingPathComponent("drive_c/SeasunGame", isDirectory: true)
        let sourceLauncher = sourceRoot.appendingPathComponent(OnlineGameMode.jx3LauncherName)
        let sourceClient = sourceRoot.appendingPathComponent(
            "Game/JX3/bin/zhcn_hd/\(OnlineGameMode.jx3ClientName)"
        )
        let sourceSettings = sourceRoot.appendingPathComponent("config/user.ini")

        try FileManager.default.createDirectory(
            at: sourceClient.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceSettings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destinationBottle.appendingPathComponent("drive_c", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: sourceLauncher.path, contents: Data("launcher".utf8))
        FileManager.default.createFile(atPath: sourceClient.path, contents: Data("client".utf8))
        try "setting=true".write(to: sourceSettings, atomically: true, encoding: .utf8)

        let result = try OnlineGameContainerMigration.migrateJX3(
            from: sourceBottle,
            to: destinationBottle
        )
        let migratedRoot = destinationBottle.appendingPathComponent(
            "drive_c/SeasunGame",
            isDirectory: true
        )

        #expect(result.didMove)
        #expect(OnlineGameDiscovery.jx3Installation(in: destinationBottle).isDetected)
        #expect(!FileManager.default.fileExists(atPath: sourceRoot.path))
        let migratedPaths = try FileManager.default.subpathsOfDirectory(atPath: migratedRoot.path)
        #expect(
            migratedPaths.contains("config/user.ini"),
            "迁移目录：\(migratedPaths)"
        )
    }

    @Test func launcherCardIsAlwaysPlayableInOnlineMode() throws {
        let fixture = try OnlineDefaultsFixture()
        defer { fixture.remove() }
        var game = Game.emptyGame
        game.id = OnlineGameMode.jx3GameID
        game.type = "launcher"
        game.isNative = false
        game.platforms = Platforms(windows: true, mac: false, linux: false)

        let store = GameCompatibilityStore(defaults: fixture.defaults)

        #expect(store.isPlayableOnMac(game))
    }

    @Test func initialConfigurationPatchesExistingIniFiles() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let config = bottle.appendingPathComponent("config.ini")
        let machineConfig = bottle.appendingPathComponent("machine_config.ini")
        try "[Debug]\nSkipVideoCardScoreUpdate=0\nOther=keep\n".write(
            to: config,
            atomically: true,
            encoding: .utf8
        )
        try "[Performance]\nDLSS=0\nOther=keep\n".write(
            to: machineConfig,
            atomically: true,
            encoding: .utf8
        )

        let patchedConfig = try OnlineGameInitialConfiguration.enforceINIValue(
            at: config,
            section: "Debug",
            key: "SkipVideoCardScoreUpdate",
            value: "1"
        )
        let patchedMachineConfig = try OnlineGameInitialConfiguration.enforceINIValue(
            at: machineConfig,
            section: "Performance",
            key: "DLSS",
            value: "1"
        )
        let configContents = try String(contentsOf: config, encoding: .utf8)
        let machineConfigContents = try String(contentsOf: machineConfig, encoding: .utf8)

        #expect(patchedConfig)
        #expect(patchedMachineConfig)
        #expect(configContents.contains("SkipVideoCardScoreUpdate=1"))
        #expect(machineConfigContents.contains("DLSS=1"))
        #expect(configContents.contains("Other=keep"))
        #expect(machineConfigContents.contains("Other=keep"))
    }

    @Test func initialConfigurationAddsMissingIniSectionAndKey() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let config = bottle.appendingPathComponent("config.ini")
        try "[Main]\nValue=keep\n".write(to: config, atomically: true, encoding: .utf8)

        let patchedConfig = try OnlineGameInitialConfiguration.enforceINIValue(
            at: config,
            section: "Debug",
            key: "SkipVideoCardScoreUpdate",
            value: "1"
        )
        let contents = try String(contentsOf: config, encoding: .utf8)
        #expect(patchedConfig)
        #expect(contents.contains("[Main]"))
        #expect(contents.contains("[Debug]"))
        #expect(contents.contains("SkipVideoCardScoreUpdate=1"))
    }

    @Test func importingJX3ConfigPresetReplacesCurrentFileAndRepairsSkipVideo() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bottle = workspace.appendingPathComponent("Games", isDirectory: true)
        let gameRoot = bottle.appendingPathComponent(
            "drive_c/SeasunGame/Game/JX3/bin/zhcn_hd",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: gameRoot, withIntermediateDirectories: true)

        let source = workspace.appendingPathComponent("normal.ini")
        let sourceContents = "[Main]\r\nCanvasWidth=2872\r\n\r\n[KG3DENGINE]\r\nAAOPTION_DLSSOption=1\r\n"
        try sourceContents.write(to: source, atomically: true, encoding: .utf8)

        let target = JX3ConfigPresetImporter.configURL(in: bottle)
        let oldContents = "[Main]\nCanvasWidth=1280\n\n[Debug]\nOld=keep\n"
        try oldContents.write(to: target, atomically: true, encoding: .utf8)

        let result = try JX3ConfigPresetImporter.importPreset(
            from: source,
            into: bottle
        )
        let imported = try String(contentsOf: target, encoding: .utf8)

        #expect(imported.contains("CanvasWidth=2872"))
        #expect(imported.contains("AAOPTION_DLSSOption=1"))
        #expect(imported.contains("SkipVideoCardScoreUpdate=1"))
        #expect(result.configURL == target)
        #expect(try String(contentsOf: source, encoding: .utf8) == sourceContents)
        let gameDirectoryFiles = try FileManager.default.contentsOfDirectory(
            at: gameRoot,
            includingPropertiesForKeys: nil
        )
        #expect(gameDirectoryFiles.map(\.lastPathComponent) == ["config.ini"])
    }

    @Test func importingGBKJX3ConfigPresetNormalizesToUTF8() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bottle = workspace.appendingPathComponent("Games", isDirectory: true)
        let gameRoot = bottle.appendingPathComponent(
            "drive_c/SeasunGame/Game/JX3/bin/zhcn_hd",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: gameRoot, withIntermediateDirectories: true)

        let gb18030Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let source = workspace.appendingPathComponent("external-gb18030-preset.ini")
        let sourceContents = "[Main]\r\nPresetName=简约\r\n\r\n[KG3DENGINE]\r\nQuality=2\r\n"
        try #require(sourceContents.data(using: gb18030Encoding)).write(to: source)

        let target = JX3ConfigPresetImporter.configURL(in: bottle)
        try "[Main]\nOld=1\n\n[KG3DENGINE]\nQuality=3\n".write(
            to: target,
            atomically: true,
            encoding: .utf8
        )

        _ = try JX3ConfigPresetImporter.importPreset(
            from: source,
            into: bottle
        )
        let importedData = try Data(contentsOf: target)
        let imported = try #require(String(data: importedData, encoding: .utf8))

        #expect(imported.contains("PresetName=简约"))
        #expect(imported.contains("Quality=2"))
        #expect(imported.contains("SkipVideoCardScoreUpdate=1"))
    }

    @Test func importingIncompleteJX3ConfigPresetIsRejectedBeforeChangingTarget() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bottle = workspace.appendingPathComponent("Games", isDirectory: true)
        let gameRoot = bottle.appendingPathComponent(
            "drive_c/SeasunGame/Game/JX3/bin/zhcn_hd",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: gameRoot, withIntermediateDirectories: true)

        let source = workspace.appendingPathComponent("not-jx3.ini")
        try "[Main]\nOnly=1\n".write(to: source, atomically: true, encoding: .utf8)
        let target = JX3ConfigPresetImporter.configURL(in: bottle)
        let oldContents = "[Main]\nOld=1\n"
        try oldContents.write(to: target, atomically: true, encoding: .utf8)

        #expect(throws: JX3ConfigPresetError.invalidPreset) {
            try JX3ConfigPresetImporter.importPreset(
                from: source,
                into: bottle
            )
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == oldContents)
    }

    @Test func configurationPollingRepairsSkipVideoAfterFileReappears() async throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let config = bottle.appendingPathComponent(
            "drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/config.ini"
        )
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        OnlineGameInitialConfiguration.startPolling(
            for: bottle,
            interval: .milliseconds(20)
        )
        try await Task.sleep(for: .milliseconds(40))
        try "[Debug]\nOther=keep\n".write(
            to: config,
            atomically: true,
            encoding: .utf8
        )
        try await Task.sleep(for: .milliseconds(120))

        let contents = try String(contentsOf: config, encoding: .utf8)
        #expect(contents.contains("SkipVideoCardScoreUpdate=1"))
        #expect(contents.contains("Other=keep"))
    }

    @Test func dlssFrameGenerationTogglePatchesJX3MachineConfig() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let machineConfig = bottle.appendingPathComponent(
            "drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/config/machine_config.ini"
        )
        try FileManager.default.createDirectory(
            at: machineConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "[Performance]\nDLSS=1\nOther=keep\n".write(
            to: machineConfig,
            atomically: true,
            encoding: .utf8
        )

        #expect(try OnlineGameInitialConfiguration.applyDLSSFrameGeneration(
            enabled: true,
            in: bottle
        ))
        var contents = try String(contentsOf: machineConfig, encoding: .utf8)
        #expect(contents.contains("DLSS=2"))
        #expect(contents.contains("Other=keep"))

        #expect(try OnlineGameInitialConfiguration.applyDLSSFrameGeneration(
            enabled: false,
            in: bottle
        ))
        contents = try String(contentsOf: machineConfig, encoding: .utf8)
        #expect(contents.contains("DLSS=1"))
    }

    @Test func legacyGameTitleDoesNotOverrideLauncherCardName() {
        var game = Game.emptyGame
        game.id = OnlineGameMode.jx3GameID
        game.type = "launcher"
        game.name = "剑网 3 启动器"

        OnlineGamePresentationStore.apply(
            OnlineGamePresentation(title: "剑网3旗舰版"),
            to: &game
        )

        #expect(game.name == "剑网 3 启动器")
    }

    @Test func localeUpsertPreservesExistingBottleVariables() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let config = bottle.appendingPathComponent("cxbottle.conf")
        try "[EnvironmentVariables]\n\"WINEDEBUG\" = \"-all\"\n[Run]".write(
            to: config,
            atomically: true,
            encoding: .utf8
        )

        try upsertCXBottleEnvironment(
            selectedBottle: bottle.absoluteString,
            values: ["LC_ALL": "zh_CN.UTF-8"]
        )

        let contents = try String(contentsOf: config, encoding: .utf8)
        #expect(contents.contains("\"WINEDEBUG\" = \"-all\""))
        #expect(contents.contains("\"LC_ALL\" = \"zh_CN.UTF-8\""))
        #expect(contents.contains("[Run]"))
    }

    @Test func bottleConfigurationSetsChineseLocaleCodepageAndFonts() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }

        try "[EnvironmentVariables]\n\"WINEDEBUG\" = \"-all\"\n".write(
            to: bottle.appendingPathComponent("cxbottle.conf"),
            atomically: true,
            encoding: .utf8
        )
        try """
            WINE REGISTRY Version 2

            [System\\\\CurrentControlSet\\\\Control\\\\Nls\\\\CodePage]
            "ACP"="1252"
            "MACCP"="10000"
            "OEMCP"="437"

            [System\\\\CurrentControlSet\\\\Control\\\\Nls\\\\Language]
            "Default"="0409"
            "InstallLanguage"="0409"

            [Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes]
            "MS Shell Dlg"="Tahoma"
            "MS Shell Dlg 2"="Tahoma"
            """.write(
                to: bottle.appendingPathComponent("system.reg"),
                atomically: true,
                encoding: .utf8
            )
        try """
            WINE REGISTRY Version 2

            [Control Panel\\\\International]
            "Locale"="00000409"

            [Keyboard Layout\\\\Preload]
            "1"="00000409"

            [Software\\\\Wine\\\\Fonts]
            "Codepages"="1252,1252"

            [Software\\\\Wine\\\\Fonts\\\\Replacements]
            "SimSun"="Tahoma"

            [Software\\\\Wine\\\\Fonts\\\\External Fonts]
            "STSong (TrueType)"="old"
            """.write(
                to: bottle.appendingPathComponent("user.reg"),
                atomically: true,
                encoding: .utf8
            )

        try OnlineGameBottleConfiguration.apply(to: bottle, fontURL: nil)

        let bottleEnvironment = try String(
            contentsOf: bottle.appendingPathComponent("cxbottle.conf"),
            encoding: .utf8
        )
        let systemRegistry = try String(
            contentsOf: bottle.appendingPathComponent("system.reg"),
            encoding: .utf8
        )
        let userRegistry = try String(
            contentsOf: bottle.appendingPathComponent("user.reg"),
            encoding: .utf8
        )

        #expect(bottleEnvironment.contains("\"LANG\" = \"zh_CN.UTF-8\""))
        #expect(bottleEnvironment.contains("\"LANGUAGE\" = \"zh_CN:zh\""))
        #expect(bottleEnvironment.contains("\"LC_ALL\" = \"zh_CN.UTF-8\""))
        #expect(systemRegistry.contains("\"ACP\"=\"936\""))
        #expect(systemRegistry.contains("\"Default\"=\"0804\""))
        #expect(systemRegistry.contains("\"MS Shell Dlg 2\"=\"STHeiti\""))
        #expect(userRegistry.contains("\"LocaleName\"=\"zh-CN\""))
        #expect(userRegistry.contains("\"1\"=\"00000804\""))
        #expect(userRegistry.contains("\"Codepages\"=\"936,936\""))
        #expect(userRegistry.contains("\"SimSun\"=\"STSong\""))
        #expect(userRegistry.contains("\"STSong (TrueType)\"=\"Z:\\\\System"))
    }

    @Test func bundledChineseFontIsCopiedIntoTheBottleAndSelected() throws {
        let bottle = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }

        try FileManager.default.createDirectory(
            at: bottle.appendingPathComponent("drive_c", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "[EnvironmentVariables]\n".write(
            to: bottle.appendingPathComponent("cxbottle.conf"),
            atomically: true,
            encoding: .utf8
        )
        try "WINE REGISTRY Version 2\n".write(
            to: bottle.appendingPathComponent("system.reg"),
            atomically: true,
            encoding: .utf8
        )
        try "WINE REGISTRY Version 2\n".write(
            to: bottle.appendingPathComponent("user.reg"),
            atomically: true,
            encoding: .utf8
        )

        let fontURL = bottle.appendingPathComponent("NotoSansCJKsc-Regular.otf")
        try Data([0x4f, 0x54, 0x54, 0x4f]).write(to: fontURL)

        try OnlineGameBottleConfiguration.apply(to: bottle, fontURL: fontURL)

        let installedFont = bottle.appendingPathComponent(
            "drive_c/windows/Fonts/NotoSansCJKsc-Regular.otf"
        )
        let systemRegistry = try String(
            contentsOf: bottle.appendingPathComponent("system.reg"),
            encoding: .utf8
        )
        let userRegistry = try String(
            contentsOf: bottle.appendingPathComponent("user.reg"),
            encoding: .utf8
        )

        #expect(FileManager.default.fileExists(atPath: installedFont.path))
        #expect(systemRegistry.contains("\"MS Shell Dlg 2\"=\"Noto Sans CJK SC\""))
        #expect(userRegistry.contains("\"SimSun\"=\"Noto Sans CJK SC\""))
        #expect(userRegistry.contains("Noto Sans CJK SC (TrueType)"))
        #expect(userRegistry.contains("C:\\\\windows\\\\Fonts"))
    }

    @Test func bundledNVNGXArchiveReplacesClientDLLsAndKeepsOriginals() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceDirectory = workspace.appendingPathComponent("nvngx-source", isDirectory: true)
        let binaryDirectory = workspace.appendingPathComponent(
            "drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/bin64",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)

        let dlss = Data([0x64, 0x6c, 0x73, 0x73])
        let dlssg = Data([0x64, 0x6c, 0x73, 0x73, 0x67])
        try dlss.write(to: sourceDirectory.appendingPathComponent("nvngx_dlss.dll"))
        try dlssg.write(to: sourceDirectory.appendingPathComponent("nvngx_dlssg.dll"))

        let archive = workspace.appendingPathComponent("nvngx-jx3.tar.xz")
        try run(
            executable: "/usr/bin/tar",
            arguments: [
                "-cJf", archive.path,
                "-C", sourceDirectory.path,
                "nvngx_dlss.dll",
                "nvngx_dlssg.dll"
            ]
        )

        let originalDLSS = Data([0x6f, 0x6c, 0x64, 0x31])
        let originalDLSSG = Data([0x6f, 0x6c, 0x64, 0x32])
        try originalDLSS.write(to: binaryDirectory.appendingPathComponent("nvngx_dlss.dll"))
        try originalDLSSG.write(to: binaryDirectory.appendingPathComponent("nvngx_dlssg.dll"))

        #expect(try BundledOnlineGameResources.installNVNGX(
            from: archive,
            into: binaryDirectory
        ))
        #expect(
            try Data(contentsOf: binaryDirectory.appendingPathComponent("nvngx_dlss.dll")) == dlss
        )
        #expect(
            try Data(contentsOf: binaryDirectory.appendingPathComponent("nvngx_dlssg.dll")) == dlssg
        )
        #expect(
            try Data(contentsOf: binaryDirectory.appendingPathComponent("nvngx_dlss.dll.orig")) == originalDLSS
        )
        #expect(
            try Data(contentsOf: binaryDirectory.appendingPathComponent("nvngx_dlssg.dll.orig")) == originalDLSSG
        )
    }

    @Test func jx3BinaryDirectoryResolvesBin64UnderGameDirectory() throws {
        let workspace = try temporaryBottle()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bottle = workspace.appendingPathComponent("Games", isDirectory: true)
        let gameRoot = bottle.appendingPathComponent(
            "drive_c/SeasunGame/Game/JX3/bin/zhcn_hd",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: gameRoot, withIntermediateDirectories: true)

        let expectedBinaryDirectory = gameRoot.appendingPathComponent("bin64", isDirectory: true)
        #expect(OnlineGameDiscovery.jx3GameDirectory(in: bottle) == gameRoot)
        #expect(OnlineGameDiscovery.jx3BinaryDirectory(in: bottle) == expectedBinaryDirectory)
    }

    @Test func customCrossOverProfilePersistsWithoutSteamAppID() throws {
        let fixture = try OnlineDefaultsFixture()
        defer { fixture.remove() }
        var game = Game.emptyGame
        game.id = OnlineGameMode.jx3GameID
        game.isNative = false
        game.isInstalled = true
        game.platforms = Platforms(windows: true, mac: false, linux: false)

        let store = GameCompatibilityStore(defaults: fixture.defaults)
        store.setCrossOverStatus(.supported, for: game)
        store.setGPTK4BetaEnabled(true, for: game)

        let reloaded = GameCompatibilityStore(defaults: fixture.defaults)
        #expect(reloaded.profile(for: game).crossOverStatus == .supported)
        #expect(reloaded.profile(for: game).gptk4BetaEnabled)
        #expect(reloaded.isPlayableOnMac(game))
    }

    private func temporaryBottle() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlineGameTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "OnlineGameTests", code: Int(process.terminationStatus))
        }
    }
}

private struct OnlineDefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "OnlineGameTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
