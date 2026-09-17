import Testing
import SwiftUI
@testable import Arclume

@MainActor
struct LauncherSidebarInsertionTests {
    private let frames = [
        "a": CGRect(x: 22, y: 80, width: 58, height: 58),
        "b": CGRect(x: 22, y: 148, width: 58, height: 58),
        "c": CGRect(x: 22, y: 216, width: 58, height: 58)
    ]

    @Test func upperAndLowerHalvesChooseSameInsertionAsDrop() {
        #expect(LauncherSidebarInsertion.target(at: CGPoint(x: 50, y: 155), source: "c", frames: frames) == .init(target: "b", after: false))
        #expect(LauncherSidebarInsertion.target(at: CGPoint(x: 50, y: 198), source: "a", frames: frames) == .init(target: "b", after: true))
    }

    @Test func gapsAndEndOfRailRemainDroppable() {
        #expect(LauncherSidebarInsertion.target(at: CGPoint(x: 50, y: 210), source: "a", frames: frames) == .init(target: "b", after: true))
        #expect(LauncherSidebarInsertion.target(at: CGPoint(x: 50, y: 280), source: "a", frames: frames) == .init(target: "c", after: true))
    }

    @Test func outsideRailAndSingleItemCancel() {
        #expect(LauncherSidebarInsertion.target(at: CGPoint(x: 200, y: 155), source: "a", frames: frames) == nil)
        #expect(LauncherSidebarInsertion.target(at: CGPoint(x: 50, y: 20), source: "a", frames: frames) == nil)
        #expect(LauncherSidebarInsertion.target(at: CGPoint(x: 50, y: 100), source: "a", frames: ["a": frames["a"]!]) == nil)
    }
}
