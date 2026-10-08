import Foundation
import Testing
@testable import Arclume

struct ResourceRequirementTests {
    private func runtime() throws -> ArclumeRuntimeManifest {
        try ArclumeRuntimeManifest.load()
    }

    private func encodedObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func catalogObject(requirements: [[String: Any]]?) throws -> [String: Any] {
        var object = try encodedObject(DownloadableResourceCatalog.load())
        if let requirements {
            object["requirements"] = requirements
        } else {
            object.removeValue(forKey: "requirements")
        }
        return object
    }

    private func decodeCatalog(_ object: [String: Any]) throws -> DownloadableResourceCatalog {
        try JSONDecoder().decode(
            DownloadableResourceCatalog.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func requirement(
        for runtime: ArclumeRuntimeManifest,
        componentIDs: [String] = [],
        features: [String: [String]] = ["steam": ["fonts"], "jx3": ["fonts"]],
        graphicsComponentIDs: [String]? = ["d3dmetal3", "d3dmetal4"],
        optionalComponentIDs: [String]? = ["nvngx-jx3"]
    ) -> [String: Any] {
        var value: [String: Any] = [
            "runtimeID": runtime.id,
            "runtimeVersion": runtime.version,
            "componentIDs": componentIDs,
            "features": features
        ]
        if let graphicsComponentIDs {
            value["graphicsComponentIDs"] = graphicsComponentIDs
        }
        if let optionalComponentIDs {
            value["optionalComponentIDs"] = optionalComponentIDs
        }
        return value
    }

    @Test func runtimePurposeSelectsOnlyTheWineArchive() throws {
        let runtime = try runtime()
        let catalog = try decodeCatalog(catalogObject(requirements: [requirement(for: runtime)]))

        let ids = try catalog.requiredIDs(for: runtime, purpose: .runtime)

        #expect(ids == Set(["io.arclume.runtime.wine"]))
    }

    @Test func steamAndJX3SelectD3DMetal4AndFonts() throws {
        let runtime = try runtime()
        let catalog = try decodeCatalog(catalogObject(requirements: [requirement(for: runtime)]))
        let expected = Set(["io.arclume.runtime.wine", "d3dmetal4", "fonts"])
        let unrelated = Set(["d3dmetal3", "dxmt", "gstreamer", "nvngx-jx3", "compatibility-libs"])

        for purpose in [DownloadableResourceCatalog.Purpose.steam, .jx3] {
            let ids = try catalog.requiredIDs(for: runtime, purpose: purpose)
            #expect(ids == expected)
            #expect(ids.isDisjoint(with: unrelated))
        }
    }

    @Test func supportedIDsIncludeOnlyConfiguredComponentsAndOptionalNVNGX() throws {
        let runtime = try runtime()
        let catalog = try decodeCatalog(catalogObject(requirements: [requirement(for: runtime)]))

        let ids = try catalog.supportedIDs(for: runtime)

        #expect(ids == Set([
            "io.arclume.runtime.wine",
            "d3dmetal3",
            "d3dmetal4",
            "fonts",
            "nvngx-jx3"
        ]))
        #expect(ids.isDisjoint(with: Set(["dxmt", "gstreamer", "compatibility-libs"])))
    }

    @Test func selectingFontsDoesNotImplicitlySelectOtherComponents() throws {
        let runtime = try runtime()
        let catalog = try decodeCatalog(catalogObject(requirements: [requirement(for: runtime)]))

        let ids = try catalog.selectedIDs(["fonts"], for: runtime)

        #expect(ids == Set(["fonts"]))
    }

    @Test func selectingArchivedButUnsupportedComponentsIsRejected() throws {
        let runtime = try runtime()
        let catalog = try decodeCatalog(catalogObject(requirements: [requirement(for: runtime)]))

        for id in ["dxmt", "gstreamer"] {
            #expect(catalog.components.contains(where: { $0.id == id }))
            #expect(throws: ResourceDownloadError.self) {
                try catalog.selectedIDs([id], for: runtime)
            }
        }
    }

    @Test func selectingWineAlsoSelectsRequiredComponents() throws {
        let runtime = try runtime()
        let requiredFonts = requirement(
            for: runtime,
            componentIDs: ["fonts"],
            features: ["steam": [], "jx3": []]
        )
        let catalog = try decodeCatalog(catalogObject(requirements: [requiredFonts]))

        let ids = try catalog.selectedIDs([runtime.id], for: runtime)

        #expect(ids == Set([runtime.id, "fonts"]))
    }

    @Test func selectedD3DMetal3BackendDoesNotAlsoRequireD3DMetal4() throws {
        let runtime = try runtime()
        let catalog = try decodeCatalog(catalogObject(requirements: [requirement(for: runtime)]))

        let ids = try catalog.requiredIDs(for: runtime, purpose: .steam, graphicsBackend: "d3dmetal3")

        #expect(ids == Set(["io.arclume.runtime.wine", "d3dmetal3", "fonts"]))
    }

    @Test func missingOrEmptyGraphicsRequirementsDoNotForceAGraphicsComponent() throws {
        let runtime = try runtime()
        let graphicsConfigurations: [[String]?] = [.some([]), .none]

        for graphicsComponentIDs in graphicsConfigurations {
            let requirements = [requirement(for: runtime, graphicsComponentIDs: graphicsComponentIDs)]
            let catalog = try decodeCatalog(catalogObject(requirements: requirements))

            for purpose in [DownloadableResourceCatalog.Purpose.steam, .jx3] {
                let ids = try catalog.requiredIDs(for: runtime, purpose: purpose)
                #expect(ids == Set(["io.arclume.runtime.wine", "fonts"]))
            }
        }
    }

    @Test func requirementsDoNotFallBackToAnotherRuntimeVersion() throws {
        let runtime = try runtime()
        var object = try catalogObject(requirements: [requirement(for: runtime)])
        var futureRuntimeObject = try encodedObject(runtime)
        futureRuntimeObject["version"] = "1.1.3"
        var runtimes = try #require(object["runtimes"] as? [[String: Any]])
        runtimes.append(futureRuntimeObject)
        object["runtimes"] = runtimes

        let catalog = try decodeCatalog(object)
        let futureRuntime = try JSONDecoder().decode(
            ArclumeRuntimeManifest.self,
            from: JSONSerialization.data(withJSONObject: futureRuntimeObject)
        )
        try catalog.validate()

        #expect(throws: ResourceDownloadError.self) {
            try catalog.requiredIDs(for: futureRuntime, purpose: .steam)
        }
    }

    @Test func requiredIDsRejectsCatalogWithoutRequirements() throws {
        let runtime = try runtime()
        let catalog = try decodeCatalog(catalogObject(requirements: nil))

        #expect(throws: ResourceDownloadError.self) {
            try catalog.requiredIDs(for: runtime, purpose: .runtime)
        }
    }

    @Test func validationRejectsUnknownGraphicsComponentReferences() throws {
        let runtime = try runtime()
        let invalidRequirement = requirement(for: runtime, graphicsComponentIDs: ["missing-graphics-component"])
        let catalog = try decodeCatalog(catalogObject(requirements: [invalidRequirement]))

        #expect(throws: ResourceDownloadError.self) {
            try catalog.validate()
        }
    }

    @Test func validationRejectsUnknownOptionalComponentReferences() throws {
        let runtime = try runtime()
        let invalidRequirement = requirement(for: runtime, optionalComponentIDs: ["missing-optional-component"])
        let catalog = try decodeCatalog(catalogObject(requirements: [invalidRequirement]))

        #expect(throws: ResourceDownloadError.self) {
            try catalog.validate()
        }
    }
}
