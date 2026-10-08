//
//  ArclumeDataMigrationTests.swift
//  ArclumeTests
//

import Foundation
import Testing
@testable import Arclume

struct ArclumeDataMigrationTests {
    @Test
    func movesLegacySupportDirectoryWithoutLeavingACopy() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("Procyon", isDirectory: true)
        let target = root.appendingPathComponent("Arclume", isDirectory: true)
        let bottleMarker = legacy.appendingPathComponent("CXPBottles/Games/drive_c/marker.txt")
        try FileManager.default.createDirectory(
            at: bottleMarker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("Games container".utf8).write(to: bottleMarker)

        #expect(migrateLegacyDirectory(from: legacy, to: target))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("CXPBottles/Games/drive_c/marker.txt").path
        ))
    }

    @Test
    func mergesOnlyMissingLegacyEntriesWhenArclumeDirectoryAlreadyExists() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("Procyon", isDirectory: true)
        let target = root.appendingPathComponent("Arclume", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("legacy bottle".utf8).write(to: legacy.appendingPathComponent("CXPBottles"))
        try Data("new configuration".utf8).write(to: target.appendingPathComponent("Settings.json"))

        #expect(migrateLegacyDirectory(from: legacy, to: target))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("CXPBottles").path))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("Settings.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArclumeDataMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
