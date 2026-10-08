import Foundation
import Testing
@testable import Arclume

@Suite(.serialized)
struct ManagedWineContainerTests {
    private func withRepository(_ body: (ManagedWineContainerRepository) throws -> Void) throws {
        let domain = "ManagedContainerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("containers-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        try body(.init(defaults: defaults, root: root))
    }

    @Test func legacyContainerIsVirtualAndUsesExistingEngine() throws {
        try withRepository { repository in
            let items = try repository.containers()
            #expect(items.count == 1)
            #expect(items[0].isDefault)
            #expect(items[0].provider == .arclume)
            #expect(items[0].prefixURL(root: repository.root) == repository.root.appendingPathComponent("ALBottles", isDirectory: true))
            #expect(repository.defaults.object(forKey: ManagedWineContainerRepository.defaultsKey) == nil)
            #expect(!FileManager.default.fileExists(atPath: repository.root.path))
            repository.defaults.set("nefinita", forKey: WineRuntimeProvider.defaultsKey)
            #expect(try repository.containers()[0].provider == .nefinita)
        }
    }

    @Test func createAndRenameDoNotTouchPrefixesOrGlobalEngine() throws {
        try withRepository { repository in
            let fm = FileManager.default
            let original = repository.root.appendingPathComponent("ALBottles/drive_c/Games/save.dat")
            try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("saved game".utf8).write(to: original)
            let item = try repository.create(name: "测试容器", provider: .nefinita)
            #expect(item.provider == .nefinita)
            #expect(UUID(uuidString: item.id) != nil)
            #expect(!fm.fileExists(atPath: item.prefixURL(root: repository.root).path))
            #expect(WineRuntimeProvider.selected(in: repository.defaults) == .arclume)
            try repository.rename(id: item.id, name: "新名称")
            #expect(try repository.container(id: item.id).name == "新名称")
            #expect(try repository.container(id: item.id).prefixURL(root: repository.root) == item.prefixURL(root: repository.root))
            #expect(try Data(contentsOf: original) == Data("saved game".utf8))
        }
    }

    @Test func displayNameNeverControlsPathsAndDuplicateNamesAreRejected() throws {
        try withRepository { repository in
            let item = try repository.create(name: "../../Display", provider: .arclume)
            #expect(item.prefixURL(root: repository.root).deletingLastPathComponent() == repository.root.appendingPathComponent("Containers", isDirectory: true))
            #expect(try repository.initializationTarget(id: item.id) == item)
            #expect(throws: ManagedContainerError.self) { try repository.create(name: "../../display", provider: .arclume) }
            #expect(throws: ManagedContainerError.self) { try repository.create(name: " \n ", provider: .arclume) }
            #expect(throws: ManagedContainerError.self) { try repository.create(name: String(repeating: "a", count: 41), provider: .arclume) }
            #expect(throws: ManagedContainerError.self) { try repository.rename(id: ManagedWineContainer.defaultID, name: "changed") }
        }
    }

    @Test func invalidCatalogIsNeverOverwritten() throws {
        try withRepository { repository in
            for data in [Data("not JSON".utf8), Data("{\"schemaVersion\":2,\"containers\":[]}".utf8),
                         Data("{\"schemaVersion\":1,\"containers\":[{\"id\":\"../outside\",\"name\":\"bad\",\"provider\":\"arclume\"}]}".utf8)] {
                repository.defaults.set(data, forKey: ManagedWineContainerRepository.defaultsKey)
                #expect(throws: ManagedContainerError.self) { try repository.containers() }
                #expect(throws: ManagedContainerError.self) { try repository.create(name: "new", provider: .arclume) }
                #expect(repository.defaults.data(forKey: ManagedWineContainerRepository.defaultsKey) == data)
            }
        }
    }

    @Test func initializationRejectsUnknownDefaultAndSymlinkTargets() throws {
        try withRepository { repository in
            #expect(throws: ManagedContainerError.self) { try repository.initializationTarget(id: "unknown") }
            #expect(throws: ManagedContainerError.self) { try repository.initializationTarget(id: ManagedWineContainer.defaultID) }
            let item = try repository.create(name: "Test", provider: .arclume)
            let parent = repository.root.appendingPathComponent("Containers", isDirectory: true)
            try FileManager.default.createDirectory(at: repository.root, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: repository.root)
            #expect(throws: ManagedContainerError.self) { try repository.initializationTarget(id: item.id) }
        }
    }

    @Test func assignmentIsDisabledInServiceAndDoesNotChangePreferences() throws {
        try withRepository { repository in
            _ = try repository.create(name: "Test", provider: .nefinita)
            let before = repository.defaults.dictionaryRepresentation()
            #expect(!GameContainerAssignmentPolicy.isEnabled)
            #expect(throws: ManagedContainerError.self) { try GameContainerAssignmentPolicy.validateAssignment() }
            #expect(NSDictionary(dictionary: before).isEqual(to: repository.defaults.dictionaryRepresentation()))
        }
    }

    @MainActor @Test func existingGameOwnershipIsDisplayedWithoutChangingIt() throws {
        try withRepository { repository in
            var game = Game.mock
            game.isNative = false
            game.installedBottleURL = URL(fileURLWithPath: repository.root.appendingPathComponent("ALBottles").path)
            let items = try repository.containers()
            #expect(GameContainerAssignmentPolicy.containerID(for: game, in: items, root: repository.root) == ManagedWineContainer.defaultID)
            game.isNative = true
            #expect(GameContainerAssignmentPolicy.containerID(for: game, in: items, root: repository.root) == nil)
        }
    }

    @Test func initializerWaitIsBoundedToItsOwnChild() throws {
        let fast = Process()
        fast.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try fast.run()
        #expect(ContainerInitializationProcess.wait(fast, timeout: 2))
        let slow = Process()
        slow.executableURL = URL(fileURLWithPath: "/bin/sleep")
        slow.arguments = ["10"]
        try slow.run()
        #expect(!ContainerInitializationProcess.wait(slow, timeout: 0.05))
        #expect(ContainerInitializationProcess.wait(slow, timeout: 2))
    }
}
