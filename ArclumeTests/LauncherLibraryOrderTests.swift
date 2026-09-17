import Testing
@testable import Arclume

struct LauncherLibraryOrderTests {
    @Test func reconcilesNewDeletedAndDuplicateIDs() {
        #expect(LauncherLibraryOrder.reconciled(saved: ["c", "deleted", "a", "c"], available: ["a", "b", "c", "d"]) == ["c", "a", "b", "d"])
    }

    @Test func reorderingPreservesFilteredOutGames() {
        let all = ["a", "hidden", "b", "c"]
        #expect(LauncherLibraryOrder.moving("c", before: "a", in: all) == ["c", "a", "hidden", "b"])
        #expect(LauncherLibraryOrder.moving("a", before: "c", in: all) == ["hidden", "b", "a", "c"])
    }

    @Test func invalidDropsDoNotChangeOrder() {
        let ids = ["a", "b"]
        #expect(LauncherLibraryOrder.moving("a", before: "a", in: ids) == ids)
        #expect(LauncherLibraryOrder.moving("external", before: "a", in: ids) == ids)
        #expect(LauncherLibraryOrder.moving("a", before: "missing", in: ids) == ids)
    }

    @Test func dropBelowLastItemCanMoveToEnd() {
        #expect(LauncherLibraryOrder.moving("a", relativeTo: "c", after: true, in: ["a", "b", "c"]) == ["b", "c", "a"])
    }

    @Test func persistenceRoundTripsAndRecoversFromMalformedSettings() {
        let ids = ["中文", "quoted\"id", "native-123"]
        #expect(LauncherLibraryOrder.decode(LauncherLibraryOrder.encode(ids)) == ids)
        #expect(LauncherLibraryOrder.decode("broken") == [])
        #expect(LauncherLibraryOrder.reconciled(saved: [], available: ids) == ids)
    }
}
