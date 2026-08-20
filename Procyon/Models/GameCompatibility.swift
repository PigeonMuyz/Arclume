//
//  GameCompatibility.swift
//  Procyon
//

import Foundation

nonisolated enum CrossOverCompatibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown
    case supported
    case unsupported

    var id: Self { self }

    var title: String {
        switch self {
        case .unknown:
            return L10n.string("Unknown")
        case .supported:
            return L10n.string("Supported")
        case .unsupported:
            return L10n.string("Not Supported")
        }
    }
}

nonisolated struct CrossOverMacRequirements: Codable, Equatable, Sendable {
    var minimum: String
    var recommended: String

    init(minimum: String = "", recommended: String = "") {
        self.minimum = minimum
        self.recommended = recommended
    }

    var isEmpty: Bool {
        minimum.isEmpty && recommended.isEmpty
    }
}

nonisolated struct GameCompatibilityProfile: Codable, Equatable, Sendable {
    var crossOverStatus: CrossOverCompatibility
    var gptk4BetaEnabled: Bool
    var crossOverMacRequirements: CrossOverMacRequirements?

    init(
        crossOverStatus: CrossOverCompatibility = .unknown,
        gptk4BetaEnabled: Bool = false,
        crossOverMacRequirements: CrossOverMacRequirements? = nil
    ) {
        self.crossOverStatus = crossOverStatus
        self.gptk4BetaEnabled = gptk4BetaEnabled
        self.crossOverMacRequirements = crossOverMacRequirements
    }

    static let defaultProfile = GameCompatibilityProfile()
}
