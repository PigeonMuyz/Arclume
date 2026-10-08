import Foundation
import Testing
@testable import Arclume

struct ResourceSetupStatusTests {
    private func status(_ runtime: ResourceSetupStatus.Runtime, missing: [String] = [], available: Bool = true) -> ResourceSetupStatus {
        ResourceSetupStatus(runtime: runtime, targetVersion: "1.1.2", missingComponents: missing,
            componentCount: 7, downloadBytes: 123, catalogAvailable: available, noticeID: "catalog-1")
    }

    @Test func currentRuntimeStillRequiresThirdPartyComponents() {
        let partial = status(.ready, missing: ["Windows 字体"])
        #expect(!partial.isReady)
        #expect(partial.actionTitle == "下载缺失组件")
        #expect(partial.runtimeDetail == "已就绪 · 1.1.2")
        #expect(partial.componentDetail.contains("Windows 字体"))
    }

    @Test func distinguishesUpgradeFromFreshDownloadAndRepair() {
        #expect(status(.missing).actionTitle == "下载运行时")
        let upgrade = status(.update(installed: "1.0.0"))
        #expect(upgrade.actionTitle == "升级运行时")
        #expect(upgrade.runtimeDetail == "可升级 · 1.0.0 → 1.1.2")
        #expect(status(.repair).actionTitle == "修复运行时")
        #expect(!status(.ready, available: false).isReady)
        #expect(status(.ready).isReady)
    }

    @Test func offersMissingResourcesOncePerCatalogWithoutRepeatingTheTour() {
        let partial = status(.ready, missing: ["兼容组件"])
        #expect(ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: true, acknowledgedNotice: "", status: partial))
        #expect(!ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: true, acknowledgedNotice: "catalog-1", status: partial))
        #expect(!ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: false, acknowledgedNotice: "", status: partial))
        #expect(!ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: true, acknowledgedNotice: "", status: status(.ready)))
        #expect(ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: true, acknowledgedNotice: "older-catalog", status: partial))
    }

    @Test func existingUsersSeeRuntimeChoiceEvenWhenEverythingIsReady() {
        let ready = status(.ready)
        #expect(ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: true,
            acknowledgedNotice: ready.noticeID, status: ready, reviewedRuntimeChoice: false))
        #expect(!ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: true,
            acknowledgedNotice: ready.noticeID, status: ready, reviewedRuntimeChoice: true))
        #expect(!ResourceSetupStatus.shouldOfferUpgrade(completedOnboarding: false,
            acknowledgedNotice: "", status: ready, reviewedRuntimeChoice: false))
    }

    #if DEBUG
    @MainActor @Test func isolatedDownloadFailureCanRetryWithoutUserFilesOrNetwork() async throws {
        let store = DownloadableResourceStore()
        store.demonstrationStatus = status(.update(installed: "1.0.0"), missing: ["兼容组件"])
        store.demonstrationFailsOnce = true
        do {
            try await store.download()
            Issue.record("The first demonstration download must fail")
        } catch {
            #expect(store.error != nil)
            #expect(!store.isBusy)
            #expect(!store.isReady)
        }
        try await store.download()
        #expect(store.isReady)
        #expect(store.progress == 1)
        #expect(store.error == nil)
        #expect(!store.isBusy)
    }
    #endif
}
