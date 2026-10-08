import Foundation
import Testing
@testable import Arclume

struct ResourceRuntimeCompatibilityTests {
    @Test func catalogCannotSubstituteANewerOrIncompatibleRuntime() throws {
        let catalog = try DownloadableResourceCatalog.load()
        let expected = try ArclumeRuntimeManifest.load()
        try catalog.validateCompatibility(with: expected)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(expected)) as? [String: Any])
        let changes: [(String, Any)] = [
            ("version", "999.0.0"), ("runtimeABI", 999),
            ("prefixABI", "other-prefix"), ("architecture", "arm64"),
            ("id", "other.runtime")
        ]
        for (field, value) in changes {
            var changed = original
            changed[field] = value
            let incompatible = try JSONDecoder().decode(ArclumeRuntimeManifest.self,
                from: JSONSerialization.data(withJSONObject: changed))
            #expect(throws: ResourceDownloadError.self) {
                try catalog.validateCompatibility(with: incompatible)
            }
        }
        var changed = original
        var archive = try #require(original["archive"] as? [String: Any])
        archive["sha256"] = String(repeating: "f", count: 64)
        changed["archive"] = archive
        let substituted = try JSONDecoder().decode(ArclumeRuntimeManifest.self,
            from: JSONSerialization.data(withJSONObject: changed))
        #expect(throws: ResourceDownloadError.self) {
            try catalog.validateCompatibility(with: substituted)
        }
    }
}
