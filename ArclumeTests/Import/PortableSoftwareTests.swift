import Foundation
import Testing
@testable import Arclume

struct PortableSoftwareTests {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("PortableTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func write(_ path: String, root: URL, value: String = "MZ-test") throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }
    private func package(_ root: URL, version: String) throws -> PortablePackage {
        let extracted = root.appendingPathComponent("extract-\(version)")
        try write("wrapper/YYSpeak/YY.exe", root: extracted, value: "MZ-\(version)")
        try write("wrapper/YYSpeak/yylauncher.exe", root: extracted)
        try write("wrapper/YYSpeak/\(version)/yyrun.exe", root: extracted)
        try write("wrapper/YYSpeak/!)绿化.bat", root: extracted, value: "DO NOT EXECUTE")
        try write("promo.url", root: extracted, value: "not imported")
        return try PortableSoftwareService.inspect(extracted)
    }
    private func bottle(_ root: URL) throws -> URL {
        let url = root.appendingPathComponent("prefix")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        return url
    }

    @Test func recognizedYYStripsWrapperAndImportsWithoutScripts() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let package = try package(root, version: "9.58")
        let choice = try #require(package.choices.first)
        #expect(package.choices.count == 1)
        #expect(choice.ruleID == "yyspeak-portable")
        #expect(choice.executable == "YY.exe")
        let bottle = try bottle(root)
        let preview = try PortableSoftwareService.preview(choice, bottle: bottle, ownedBottles: [bottle])
        let (candidate, recovery) = try PortableSoftwareService.install(preview, ownedBottles: [bottle], requireIdle: {})
        #expect(recovery == nil)
        #expect(candidate.executable == bottle.appendingPathComponent("drive_c/PortableApps/YYSpeak/YY.exe"))
        #expect(!FileManager.default.fileExists(atPath: preview.destination.appendingPathComponent("promo.url").path))
        #expect(try String(contentsOf: preview.destination.appendingPathComponent("!)绿化.bat"), encoding: .utf8) == "DO NOT EXECUTE")
        let plan = try GameRemovalService.plan(executable: candidate.executable, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
        #expect(plan.directory.path == preview.destination.path)
        #expect(plan.launcher == nil)
    }

    @Test func updateReplacesTreeKeepsDataAndProvidesFullRecovery() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = try bottle(root)
        let v1 = try #require(package(root, version: "1").choices.first)
        let first = try PortableSoftwareService.preview(v1, bottle: bottle, ownedBottles: [bottle])
        let original = try PortableSoftwareService.install(first, ownedBottles: [bottle], requireIdle: {})
        try write("user-note.txt", root: first.destination, value: "personal")
        try write("settings/value.ini", root: first.destination, value: "keep setting")
        try write("drive_c/users/test/AppData/Roaming/duowan/yy/account.dat", root: bottle, value: "account")
        try write("user.reg", root: bottle, value: "registry unchanged")
        let v2 = try #require(package(root, version: "2").choices.first)
        let preserving = PortableChoice(id: v2.id, name: v2.name, root: v2.root, executable: v2.executable,
            installDirectory: v2.installDirectory, ruleID: v2.ruleID, preservePaths: ["settings"])
        let next = try PortableSoftwareService.preview(preserving, bottle: bottle, ownedBottles: [bottle])
        #expect(next.isUpdate)
        let (updated, recovery) = try PortableSoftwareService.install(next, ownedBottles: [bottle], requireIdle: {})
        #expect(updated.executable == original.0.executable)
        #expect(try String(contentsOf: updated.executable, encoding: .utf8) == "MZ-2")
        #expect(!FileManager.default.fileExists(atPath: next.destination.appendingPathComponent("1").path))
        #expect(try String(contentsOf: next.destination.appendingPathComponent("settings/value.ini"), encoding: .utf8) == "keep setting")
        let old = try #require(recovery).appendingPathComponent("previous")
        #expect(try String(contentsOf: old.appendingPathComponent("YY.exe"), encoding: .utf8) == "MZ-1")
        #expect(try String(contentsOf: old.appendingPathComponent("user-note.txt"), encoding: .utf8) == "personal")
        #expect(try String(contentsOf: bottle.appendingPathComponent("user.reg"), encoding: .utf8) == "registry unchanged")
        #expect(try String(contentsOf: bottle.appendingPathComponent("drive_c/users/test/AppData/Roaming/duowan/yy/account.dat"), encoding: .utf8) == "account")
        #expect(throws: (any Error).self) { try PortableSoftwareService.install(next, ownedBottles: [bottle], requireIdle: {}) }
    }

    @Test func failureAndRunningChecksNeverReplaceOldVersion() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = try bottle(root)
        let v1 = try #require(package(root, version: "1").choices.first)
        let first = try PortableSoftwareService.preview(v1, bottle: bottle, ownedBottles: [bottle])
        _ = try PortableSoftwareService.install(first, ownedBottles: [bottle], requireIdle: {})
        let v2 = try #require(package(root, version: "2").choices.first)
        let next = try PortableSoftwareService.preview(v2, bottle: bottle, ownedBottles: [bottle])
        #expect(throws: (any Error).self) {
            try PortableSoftwareService.install(next, ownedBottles: [bottle], requireIdle: { throw GameRemovalError.running })
        }
        #expect(throws: (any Error).self) {
            try PortableSoftwareService.install(next, ownedBottles: [bottle], requireIdle: {}, exchange: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        }
        #expect(try String(contentsOf: first.destination.appendingPathComponent("YY.exe"), encoding: .utf8) == "MZ-1")
        #expect(try PortableSoftwareService.readReceipt(at: first.destination) == next.previous)
    }

    @Test func unknownSoftwareKeepsRootAndRequiresEntryChoice() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("wrapper/bin/Voice.exe", root: root)
        try write("wrapper/tools/Helper.exe", root: root)
        try write("wrapper/resource.dat", root: root)
        let package = try PortableSoftwareService.inspect(root)
        #expect(package.choices.count == 2)
        #expect(package.choices.allSatisfy { $0.ruleID == nil && $0.root.path == root.appendingPathComponent("wrapper").path })
        #expect(Set(package.choices.map(\.executable)) == ["bin/Voice.exe", "tools/Helper.exe"])
    }

    @Test func unmanagedDirectoriesUnownedPrefixesAndSymlinksAreRejected() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = try bottle(root), choice = try #require(package(root, version: "1").choices.first)
        #expect(throws: (any Error).self) { try PortableSoftwareService.preview(choice, bottle: bottle, ownedBottles: []) }
        let target = bottle.appendingPathComponent("drive_c/PortableApps/YYSpeak")
        try write("YY.exe", root: target)
        #expect(throws: (any Error).self) { try PortableSoftwareService.preview(choice, bottle: bottle, ownedBottles: [bottle]) }
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: choice.root)
        #expect(throws: (any Error).self) { try PortableSoftwareService.preview(choice, bottle: bottle, ownedBottles: [bottle]) }
        try FileManager.default.createSymbolicLink(at: choice.root.appendingPathComponent("link"), withDestinationURL: root)
        #expect(throws: (any Error).self) { try PortableSoftwareService.checkedTree(choice.root) }
    }

    // Tiny ZIP writer keeps hostile names in isolated in-memory fixtures, never in real folders.
    private func zip(_ entries: [(String, Data)], to url: URL) throws {
        var data = Data(), central = Data()
        func integer(_ value: UInt32, width: Int, into output: inout Data) {
            for shift in 0..<width { output.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
        }
        func crc(_ input: Data) -> UInt32 {
            var crc: UInt32 = 0xffff_ffff
            for byte in input {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb8_8320 : 0) }
            }
            return ~crc
        }
        for (name, body) in entries {
            let path = Data(name.utf8), offset = UInt32(data.count), checksum = crc(body)
            for (n, width) in [(UInt32(0x04034b50), 4), (20, 2), (0x800, 2), (0, 2), (0, 2), (0, 2), (checksum, 4), (UInt32(body.count), 4), (UInt32(body.count), 4), (UInt32(path.count), 2), (0, 2)] { integer(n, width: width, into: &data) }
            data.append(path); data.append(body)
            for (n, width) in [(UInt32(0x02014b50), 4), (20, 2), (20, 2), (0x800, 2), (0, 2), (0, 2), (0, 2), (checksum, 4), (UInt32(body.count), 4), (UInt32(body.count), 4), (UInt32(path.count), 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 4), (offset, 4)] { integer(n, width: width, into: &central) }
            central.append(path)
        }
        let offset = UInt32(data.count); data.append(central)
        for (n, width) in [(UInt32(0x06054b50), 4), (0, 2), (0, 2), (UInt32(entries.count), 2), (UInt32(entries.count), 2), (UInt32(central.count), 4), (offset, 4), (0, 2)] { integer(n, width: width, into: &data) }
        try data.write(to: url)
    }

    @Test func zipExtractionAndUTF8Names() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("voice.zip"), extracted = root.appendingPathComponent("extracted")
        try zip([("语音/YY.exe", Data("MZ".utf8)), ("语音/!)绿化.bat", Data("do not run".utf8))], to: archive)
        try PortableArchiveReader.extract(archive, to: extracted)
        #expect(try String(contentsOf: extracted.appendingPathComponent("语音/!)绿化.bat"), encoding: .utf8) == "do not run")
    }

    @Test func traversalDuplicatesReservedNamesAndLimitsFailClosed() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for names in [["../escape"], ["/absolute"], ["C:/windows/file"], ["..\\escape"], ["NUL.txt"], ["folder./file"], ["a.exe", "a.exe"], ["A/file", "a/other"], [PortableSoftwareService.receiptName]] {
            let archive = root.appendingPathComponent(UUID().uuidString + ".zip"), extracted = root.appendingPathComponent(UUID().uuidString)
            try zip(names.map { ($0, Data("MZ".utf8)) }, to: archive)
            #expect(throws: (any Error).self, "paths: \(names)") { try PortableArchiveReader.extract(archive, to: extracted) }
            #expect(!FileManager.default.fileExists(atPath: extracted.path), "paths: \(names)")
        }
        let archive = root.appendingPathComponent("large.zip"), extracted = root.appendingPathComponent("limited")
        try zip([("one", Data(repeating: 1, count: 40)), ("two", Data(repeating: 2, count: 40))], to: archive)
        #expect(throws: (any Error).self) { try PortableArchiveReader.extract(archive, to: extracted, byteLimit: 60) }
        #expect(throws: (any Error).self) { try PortableArchiveReader.extract(archive, to: extracted, entryLimit: 1) }
        #expect(!FileManager.default.fileExists(atPath: extracted.path))
    }

    @Test func sevenZipAndArchiveSymlinkHandling() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try write("YY.exe", root: source)
        func tar(_ format: String, archive: URL, name: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["--format=" + format, "-cf", archive.path, "-C", source.path, name]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        let seven = root.appendingPathComponent("voice.7z")
        try tar("7zip", archive: seven, name: "YY.exe")
        try PortableArchiveReader.extract(seven, to: root.appendingPathComponent("seven"))
        #expect(PortableSoftwareService.isExecutable(root.appendingPathComponent("seven/YY.exe")))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: root)
        let linked = root.appendingPathComponent("linked.zip")
        try tar("zip", archive: linked, name: "link")
        #expect(throws: (any Error).self) { try PortableArchiveReader.extract(linked, to: root.appendingPathComponent("linked")) }
    }

    @Test func corruptArchivesAndUnsafeRulesAreRejected() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for ext in PortableArchiveReader.extensions {
            let file = root.appendingPathComponent("broken." + ext)
            try Data("not an archive".utf8).write(to: file)
            #expect(throws: (any Error).self) { try PortableArchiveReader.extract(file, to: root.appendingPathComponent("out")) }
        }
        let source = #"{"schemaVersion":1,"rules":[{"id":"test","name":"Voice","kind":"application","installDirectory":"PortableApps/Voice","executable":"Voice.exe","alternateExecutables":[],"requiredFiles":["marker.dll"],"defaultArguments":[],"portable":{"scriptPolicy":"skip","preservePaths":["settings"]}}]}"#
        #expect(try GameAdaptationRules.decode(Data(source.utf8)).count == 1)
        for invalid in [source.replacingOccurrences(of: "skip", with: "run-bat"),
                        source.replacingOccurrences(of: "PortableApps/Voice", with: "windows/system32"),
                        source.replacingOccurrences(of: "settings", with: "../other"),
                        source.replacingOccurrences(of: "settings", with: "Voice.exe")] {
            #expect(throws: (any Error).self) { try GameAdaptationRules.decode(Data(invalid.utf8)) }
        }
    }

    @MainActor @Test func explicitReimportRestoresHiddenEntryAndUpdateDoesNotDuplicateIt() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bottle = try bottle(root), choice = try #require(package(root, version: "1").choices.first)
        let preview = try PortableSoftwareService.preview(choice, bottle: bottle, ownedBottles: [bottle])
        let (candidate, _) = try PortableSoftwareService.install(preview, ownedBottles: [bottle], requireIdle: {})
        try #require(ArclumeTestEnvironment.isTesting)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let originalGames = defaults.data(forKey: "customAddedGames")
        let originalHidden = defaults.stringArray(forKey: "hiddenInstalledGames.v1")
        defer {
            defaults.set(originalGames, forKey: "customAddedGames")
            defaults.set(originalHidden, forKey: "hiddenInstalledGames.v1")
        }
        let identity = GameRemovalService.identity(executable: candidate.executable, bottle: bottle)
        defaults.set([identity], forKey: "hiddenInstalledGames.v1")
        let library = LibraryPageGlobals()
        library.customAddedGames = []
        library.addInstalledProgram(candidate, bottle: bottle, runtimeKind: "bundledWine", crossOverPath: nil)
        #expect(library.customAddedGames.isEmpty)
        library.addInstalledProgram(candidate, bottle: bottle, runtimeKind: "bundledWine", crossOverPath: nil, userInitiated: true)
        let first = try #require(library.customAddedGames.first)
        library.addInstalledProgram(candidate, bottle: bottle, runtimeKind: "bundledWine", crossOverPath: nil, userInitiated: true)
        #expect(library.customAddedGames.count == 1)
        #expect(library.customAddedGames[0].id == first.id)
        #expect(defaults.stringArray(forKey: "hiddenInstalledGames.v1") == [])
    }
}
