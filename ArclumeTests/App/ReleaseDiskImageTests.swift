import Foundation
import Testing
@testable import Arclume

struct ReleaseDiskImageTests {
    private func release(_ names: [String]) -> ArclumeGitHubRelease {
        ArclumeGitHubRelease(tagName: "v2.0", name: "Arclume", body: nil,
            htmlURL: URL(string: "https://example.invalid/release")!, publishedAt: nil,
            assets: names.enumerated().map { index, name in
                .init(id: index, name: name, digest: nil,
                      browserDownloadURL: URL(string: "https://example.invalid/\(name)")!)
            })
    }

    @Test func prefersUnifiedPackageButStillSupportsOldReleases() {
        #expect(release(["Arclume-2.0-with-runtime.dmg", "Arclume-2.0-no-runtime.dmg", "Arclume-2.0.dmg"]).diskImage?.name == "Arclume-2.0.dmg")
        #expect(release(["Arclume-2.0-with-runtime.dmg", "Arclume-2.0-no-runtime.dmg"]).diskImage?.name == "Arclume-2.0-no-runtime.dmg")
        #expect(release(["Arclume-2.0-with-runtime.dmg"]).diskImage?.name == "Arclume-2.0-with-runtime.dmg")
        #expect(release(["notes.txt"]).diskImage == nil)
    }
}
