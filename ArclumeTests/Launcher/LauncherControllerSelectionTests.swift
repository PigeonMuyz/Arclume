import Testing
@testable import Arclume

@MainActor
struct LauncherControllerSelectionTests {
    private let ids = ["steam", "jx3", "custom"]

    @Test func previousAndNextFollowStoredOrder() {
        #expect(LauncherControllerSelection.next(in: ids, selected: "jx3", step: -1) == "steam")
        #expect(LauncherControllerSelection.next(in: ids, selected: "jx3", step: 1) == "custom")
    }

    @Test func selectionWrapsAtBothEnds() {
        #expect(LauncherControllerSelection.next(in: ids, selected: "steam", step: -1) == "custom")
        #expect(LauncherControllerSelection.next(in: ids, selected: "custom", step: 1) == "steam")
    }

    @Test func emptyAndSingleItemListsAreHandled() {
        #expect(LauncherControllerSelection.next(in: [], selected: "steam", step: 1) == nil)
        #expect(LauncherControllerSelection.next(in: ["steam"], selected: "steam", step: -1) == "steam")
        #expect(LauncherControllerSelection.next(in: ["steam"], selected: nil, step: 1) == "steam")
    }

    @Test func missingSelectionStartsAtFirstIndexBeforeApplyingStep() {
        #expect(LauncherControllerSelection.next(in: ids, selected: "missing", step: 0) == "steam")
        #expect(LauncherControllerSelection.next(in: ids, selected: "missing", step: 1) == "jx3")
        #expect(LauncherControllerSelection.next(in: ids, selected: "missing", step: -1) == "custom")
    }
}
