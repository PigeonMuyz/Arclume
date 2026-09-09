import AppKit
import Foundation
import Testing
@testable import Arclume

struct WindowsProgramPresentationTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("PresentationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func exe(_ name: String, root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: url)
        return url
    }

    @Test func globalNameIsClearedAndOnlyExactScopedProcessesAreNamed() throws {
        let bottle = try root(); defer { try? FileManager.default.removeItem(at: bottle) }
        let old = ["PROCYON_WINE_DOCK_NAME": "剑网3旗舰版", "WINEPRELOADERAPPNAME": "剑网3旗舰版", "KEEP": "1"]
        #expect(GameAdaptationRules.processEnvironment(old) == ["KEEP": "1"])
        let yy = try #require(GameAdaptationRules.rule(id: "yyspeak-portable"))
        let main = try exe("drive_c/\(yy.installDirectory)/YY.exe", root: bottle)
        _ = try exe("drive_c/\(yy.installDirectory)/yylauncher.exe", root: bottle)
        #expect(GameAdaptationRules.processEnvironment(old, executable: main, bottle: bottle) == ["KEEP": "1", "WINEPRELOADERAPPNAME": "YY语音"])
        let helper = try exe("drive_c/\(yy.installDirectory)/9.58.0.0/yyexternal.exe", root: bottle)
        #expect(GameAdaptationRules.processEnvironment(old, executable: helper, bottle: bottle) == ["KEEP": "1"])
        let fake = try exe("drive_c/Other/YY.exe", root: bottle)
        _ = try exe("drive_c/Other/yylauncher.exe", root: bottle)
        #expect(GameAdaptationRules.processName(for: fake, bottle: bottle) == nil)
        let jx3 = try exe("drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/JX3ClientX64.exe", root: bottle)
        #expect(GameAdaptationRules.processName(for: jx3, bottle: bottle) == "剑网3旗舰版")
        let unknown = try exe("drive_c/Other/JX3ClientX64.exe", root: bottle)
        #expect(GameAdaptationRules.processName(for: unknown, bottle: bottle) == nil)
        let game = try #require(GameAdaptationRules.rule(id: "endfield"))
        let endfield = try exe("drive_c/\(game.installDirectory)/Endfield.exe", root: bottle)
        for file in game.requiredFiles { _ = try exe("drive_c/\(game.installDirectory)/\(file)", root: bottle) }
        #expect(GameAdaptationRules.processName(for: endfield, bottle: bottle) == "明日方舟：终末地")
    }

    private func peFixture() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 64, bitsPerPixel: 32)!
        bitmap.bitmapData!.initialize(repeating: 255, count: 1024)
        let png = bitmap.representation(using: .png, properties: [:])!
        var data = Data(repeating: 0, count: 1536)
        func set(_ offset: Int, _ value: Int, _ width: Int = 4) {
            for index in 0..<width { data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
        }
        set(0, 0x5a4d, 2); set(0x3c, 0x80); set(0x80, 0x4550)
        set(0x86, 1, 2); set(0x94, 224, 2); set(0x98, 0x10b, 2)
        set(0x98 + 92, 16); set(0x98 + 112, 0x1000); set(0x98 + 116, 1024)
        let section = 0x98 + 224
        set(section + 12, 0x1000); set(section + 16, 1024); set(section + 20, 512)
        let base = 512
        set(base + 14, 2, 2)
        set(base + 16, 3); set(base + 20, 0x80000020)
        set(base + 24, 14); set(base + 28, 0x80000038)
        set(base + 32 + 14, 1, 2); set(base + 48, 1); set(base + 52, 0x80000050)
        set(base + 56 + 14, 1, 2); set(base + 72, 1); set(base + 76, 0x80000068)
        set(base + 80 + 14, 1, 2); set(base + 96, 1033); set(base + 100, 128)
        set(base + 104 + 14, 1, 2); set(base + 120, 1033); set(base + 124, 144)
        set(base + 128, 0x1000 + 200); set(base + 132, png.count)
        set(base + 144, 0x1000 + 160); set(base + 148, 20)
        set(base + 162, 1, 2); set(base + 164, 1, 2)
        set(base + 166, 16, 1); set(base + 167, 16, 1); set(base + 170, 1, 2); set(base + 172, 32, 2)
        set(base + 174, png.count); set(base + 178, 1, 2)
        data.replaceSubrange((base + 200)..<(base + 200 + png.count), with: png)
        return data
    }

    @Test func extractsGroupedIconWithoutExecutingPE() throws {
        let icon = try #require(WindowsExecutableIcon.ico(in: peFixture()))
        #expect(icon.prefix(6) == Data([0, 0, 1, 0, 1, 0]))
        #expect(NSImage(data: icon) != nil)
    }

    @Test func truncatedAndCyclicResourceTreesFailWithoutReadingOutsideFile() {
        let data = peFixture()
        for size in [0, 2, 63, 127, 180, 500, 800] {
            #expect(WindowsExecutableIcon.ico(in: Data(data.prefix(size))) == nil)
        }
        var cyclic = data
        cyclic[512 + 20] = 0; cyclic[512 + 21] = 0; cyclic[512 + 22] = 0; cyclic[512 + 23] = 0x80
        #expect(WindowsExecutableIcon.ico(in: cyclic) == nil)
        #expect(WindowsExecutableIcon.ico(in: Data(repeating: 255, count: 1024)) == nil)
    }

    @Test func diagnosticLogIsBounded() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("fixture.log")
        let capture = try WindowsProgramDiagnosticLog(url: log)
        capture.append(Data(repeating: 65, count: WindowsProgramDiagnosticLog.byteLimit + 512))
        capture.append(Data(repeating: 66, count: 512))
        capture.finish()
        let data = try Data(contentsOf: log)
        #expect(data.count < WindowsProgramDiagnosticLog.byteLimit + 200)
        #expect(data.prefix(WindowsProgramDiagnosticLog.byteLimit).allSatisfy { $0 == 65 })
        #expect(String(decoding: data.suffix(100), as: UTF8.self).contains("output omitted"))
    }

    @Test func capturesChildErrorsAfterLauncherExitsAndClosesAtEOF() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("children.log")
        let capture = try WindowsProgramDiagnosticLog(url: log)
        defer { capture.finish() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf first >&2; (sleep 0.05; printf second >&2) &"]
        capture.attach(to: process)
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !capture.isFinished, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(capture.isFinished)
        #expect(try String(contentsOf: log, encoding: .utf8) == "firstsecond")
    }
}
