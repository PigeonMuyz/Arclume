import Foundation
import Testing

@testable import Arclume

@MainActor
struct CrossOverConfigurationTests {
    @Test func readsExistingBottleConfigurationWithoutChangingApplicationOrBottle() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ArclumeCrossOverConfiguration-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let app = root.appendingPathComponent("CrossOver.app", isDirectory: true)
        let configuration = app.appendingPathComponent("Contents/SharedSupport/CrossOver/etc/CrossOver.conf")
        let bottles = root.appendingPathComponent("Existing Bottles", isDirectory: true)
        let bottle = bottles.appendingPathComponent("Games", isDirectory: true)
        let savedData = bottle.appendingPathComponent("user.reg")
        try fileManager.createDirectory(at: configuration.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bottle, withIntermediateDirectories: true)
        let configurationData = Data("[EnvironmentVariables]\n\"CX_BOTTLE_PATH\" = \"\(bottles.path)\"\n".utf8)
        let userData = Data("existing user configuration".utf8)
        try configurationData.write(to: configuration)
        try userData.write(to: savedData)

        #expect(try getCrossOverBottlesURL(appDir: app).path == bottles.path)
        let discoveredBottles = try getAllBottles(appDir: app)
            .map { $0.resolvingSymlinksInPath().path }
        #expect(discoveredBottles == [bottle.resolvingSymlinksInPath().path])
        #expect(try Data(contentsOf: configuration) == configurationData)
        #expect(try Data(contentsOf: savedData) == userData)
        #expect(try fileManager.contentsOfDirectory(atPath: root.path).sorted() == ["CrossOver.app", "Existing Bottles"])
    }
}
