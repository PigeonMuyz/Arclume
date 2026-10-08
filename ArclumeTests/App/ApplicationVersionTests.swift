import Testing
@testable import Arclume

struct ApplicationVersionTests {
    @Test func plainVersionUpdatesOlderMarketingVersion() {
        #expect(ArclumeVersionComparison.isApplicationUpdateAvailable(
            releaseTag: "v1.0.4", currentMarketingVersion: "1.0.3", currentBuild: "8"))
        #expect(!ArclumeVersionComparison.isApplicationUpdateAvailable(
            releaseTag: "v1.0.4", currentMarketingVersion: "1.0.4", currentBuild: "9"))
        #expect(ArclumeVersionComparison.applicationReleaseComponents("v1.0.4").buildNumber == nil)
    }

    @Test func legacyBuildTagsRemainCompatibleWithoutOfferingDowngrades() {
        #expect(!ArclumeVersionComparison.isApplicationUpdateAvailable(
            releaseTag: "v1.0.3-8", currentMarketingVersion: "1.0.4", currentBuild: "9"))
        #expect(ArclumeVersionComparison.isApplicationUpdateAvailable(
            releaseTag: "v1.0.3-8", currentMarketingVersion: "1.0.3", currentBuild: "7"))
    }
}
