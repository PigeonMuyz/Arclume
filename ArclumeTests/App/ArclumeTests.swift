import Foundation
import Testing
@testable import Arclume

struct ArclumeTests {
    @Test func testHostUsesIsolatedPreferences() {
        #expect(ArclumeTestEnvironment.isTesting)
        #expect(suiteName.hasPrefix("io.github.pigeonmuyz.arclume.tests."))
        #expect(suiteName != "group.io.github.pigeonmuyz.arclume")
    }

    @Test func shippedAdaptationsHaveUniqueIdentifiers() {
        let rules = GameAdaptationRules.all
        #expect(!rules.isEmpty)
        #expect(Set(rules.map(\.id)).count == rules.count)
    }
}
