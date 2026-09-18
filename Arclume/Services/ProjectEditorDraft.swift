import Foundation

/// Only display fields can be adopted; executable and container identity are not representable.
nonisolated struct ProjectMetadataSelection: Equatable {
    var text = true
    var background = true
    var logo = true

    func applying(_ incoming: ProjectPresentation, to current: ProjectPresentation) -> ProjectPresentation {
        var result = current
        if text {
            result.name = incoming.name ?? current.name
            result.summary = incoming.summary ?? current.summary
        }
        if background {
            result.background = ProjectMetadataAdoption.image(incoming.background, keeping: current.background ?? "")
        }
        if logo {
            result.logo = ProjectMetadataAdoption.image(incoming.logo, keeping: current.logo ?? "")
        }
        if text || (background && incoming.background != nil) || (logo && incoming.logo != nil) {
            result.metadataSource = incoming.metadataSource ?? current.metadataSource
        }
        return result
    }
}

nonisolated enum ProjectEditorValidation {
    static func imageAddress(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard let url = URL(string: value) else { return false }
        if url.isFileURL { return !url.path.isEmpty }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }
}
