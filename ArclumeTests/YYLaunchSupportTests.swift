import Foundation
import Testing
@testable import Arclume

struct YYLaunchSupportTests {
    @Test func bundledHelperAndRuleAgree() throws {
        let rule = try #require(GameAdaptationRules.rule(id: "yyspeak-portable"))
        #expect(rule.launchSupport == "yy-9.58-v1")
        let helper = try #require(Bundle.main.url(forResource: "yy-launch-support", withExtension: "exe"))
        try YYLaunchSupport.verify(helper, sha256: YYLaunchSupport.helperSHA256)
        #expect(throws: (any Error).self) { try YYLaunchSupport.verify(helper, sha256: String(repeating: "0", count: 64)) }
    }

    @Test func unrelatedProgramsDoNotUseHelper() throws {
        #expect(try YYLaunchSupport.arguments(executable: nil, bottle: URL(fileURLWithPath: "/unused"), userArguments: ["-test"], helper: nil) == nil)
    }

    @Test func unsupportedVersionAndMissingHelperFailClosed() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("YYSupportTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("drive_c/PortableApps/YYSpeak")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("YY.exe")
        try Data([0x4d, 0x5a]).write(to: executable)
        #expect(throws: (any Error).self) { try YYLaunchSupport.arguments(executable: executable, bottle: root, userArguments: [], helper: nil) }
        try Data([0x4d, 0x5a]).write(to: directory.appendingPathComponent("yylauncher.exe"))
        #expect(throws: (any Error).self) { try YYLaunchSupport.arguments(executable: executable, bottle: root, userArguments: [], helper: nil) }
        #expect(throws: (any Error).self) { try YYLaunchSupport.arguments(executable: executable, bottle: root, userArguments: []) }
        #expect(throws: (any Error).self) { try YYLaunchSupport.arguments(executable: executable, bottle: root, userArguments: ["--debugport=9222"]) }
    }

    @Test func ruleCannotAssignHelperToOtherPrograms() throws {
        let source = """
        {"schemaVersion":1,"rules":[{"id":"another","name":"Test","kind":"application","installDirectory":"PortableApps/Test","executable":"Test.exe","alternateExecutables":[],"requiredFiles":[],"defaultArguments":[],"captureErrors":true,"launchSupport":"yy-9.58-v1"}]}
        """
        #expect(throws: (any Error).self) { try GameAdaptationRules.decode(Data(source.utf8)) }
        let invalidID = source.replacingOccurrences(of: "yy-9.58-v1", with: "arbitrary-helper")
        #expect(throws: (any Error).self) { try GameAdaptationRules.decode(Data(invalidID.utf8)) }
    }
}
