import Foundation
import Testing
@testable import Arclume

struct ProjectMetadataCatalogTests {
    @Test func appStoreNameSearchUsesSelectedRegionAndPlatform() throws {
        let url = try AppStoreCatalogService.requestURL(query: "星露谷 & Valley", country: "CN", macOnly: true)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host == "itunes.apple.com")
        #expect(url.path == "/search")
        #expect(items.first { $0.name == "term" }?.value == "星露谷 & Valley")
        #expect(items.first { $0.name == "country" }?.value == "cn")
        #expect(items.first { $0.name == "entity" }?.value == "macSoftware")
    }

    @Test func appStoreLinkAndIDUseLookup() throws {
        for input in ["409183694", "https://apps.apple.com/us/app/keynote/id409183694?mt=12"] {
            let url = try AppStoreCatalogService.requestURL(query: input, country: "us", macOnly: false)
            #expect(url.path == "/lookup")
            #expect(url.query?.contains("id=409183694") == true)
            #expect(url.query?.contains("entity=software") == true)
        }
    }

    @Test func appStoreRejectsForeignLinks() {
        for input in ["https://example.com/id42", "file:///fixture/id42", "https://apps.apple.com/not-an-id"] {
            #expect(throws: (any Error).self) {
                try AppStoreCatalogService.requestURL(query: input, country: "us", macOnly: true)
            }
        }
    }

    @Test func catalogDecodesOptionalFieldsAndActualPlatform() throws {
        let data = Data(#"{"results":[{"trackId":42,"trackName":"示例","kind":"mac-software","artworkUrl512":"https://example.com/icon.png","screenshotUrls":["https://example.com/screen.jpg"]},{"trackId":43,"trackName":"Mobile","kind":"software"}]}"#.utf8)
        let items = try AppStoreCatalogService.decode(data)
        #expect(items.count == 2)
        #expect(items[0].platformLabel == "Mac")
        #expect(items[1].platformLabel == "iPhone / iPad")
        #expect(items[0].background == "https://example.com/screen.jpg")
        #expect(items[1].background == nil)
        #expect(items[0].iconURL?.lastPathComponent == "icon.png")
    }

    @Test func adoptionSynchronizesLogoAndPreservesMissingAssets() {
        #expect(ProjectMetadataAdoption.image("https://example.com/logo.png", keeping: "old") == "https://example.com/logo.png")
        #expect(ProjectMetadataAdoption.image(nil, keeping: "file:///fixture/logo.png") == "file:///fixture/logo.png")
        #expect(ProjectMetadataAdoption.image("", keeping: "old") == "old")
        #expect(ProjectMetadataAdoption.image("javascript:bad", keeping: "old") == "old")
    }

    @Test func invalidSteamIDDoesNotRequestNetwork() async {
        let artwork = await SteamProjectArtworkService().artwork(appID: 0)
        #expect(artwork.logo == nil)
        #expect(artwork.background == nil)
    }
}
