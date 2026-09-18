import Foundation
import Testing
@testable import Arclume

struct ProjectEditorDraftTests {
    private let current = ProjectPresentation(name: "本地名称", summary: "本地简介",
        background: "file:///fixture/background.png", logo: "file:///fixture/logo.png")

    @Test func selectionOnlyChangesChosenFields() {
        let incoming = ProjectPresentation(name: "新名称", summary: "新简介",
            background: "https://example.com/hero.jpg", logo: "https://example.com/logo.png")
        let selected = ProjectMetadataSelection(text: false, background: true, logo: false)
        let result = selected.applying(incoming, to: current)
        #expect(result.name == current.name)
        #expect(result.summary == current.summary)
        #expect(result.background == incoming.background)
        #expect(result.logo == current.logo)
    }

    @Test func missingOrInvalidAssetsPreserveLocalArtwork() {
        let result = ProjectMetadataSelection().applying(
            ProjectPresentation(name: "App Store 项目", background: "javascript:invalid"), to: current)
        #expect(result.name == "App Store 项目")
        #expect(result.background == current.background)
        #expect(result.logo == current.logo)
    }

    @Test func deselectingAllPreservesEntireDraft() {
        let incoming = ProjectPresentation(name: "另一个名称", metadataSource: .init(provider: "steam", id: "42", language: "schinese"))
        #expect(ProjectMetadataSelection(text: false, background: false, logo: false)
            .applying(incoming, to: current) == current)
    }

    @Test func validatesImageAddressesWithoutNetwork() {
        for value in ["", "https://example.com/a.png", "http://localhost/a.png", "file:///fixture/logo.png"] {
            #expect(ProjectEditorValidation.imageAddress(value))
        }
        for value in ["javascript:alert(1)", "relative/image.png", "https:///", "ftp://example.com/a.png"] {
            #expect(!ProjectEditorValidation.imageAddress(value))
        }
    }
}
