//
//  GameCompatibilityEditor.swift
//  Procyon
//

import SwiftUI

struct GameCompatibilityEditor: View {
    let game: Game

    @EnvironmentObject private var compatibilityStore: GameCompatibilityStore

    var body: some View {
        if game.supportsCrossOverCompatibility {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Mac Compatibility"))
                    .font(.headline)

                if game.isNative || game.platforms.mac {
                    Label(L10n.string("Native macOS"), systemImage: "apple.logo")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker(L10n.string("CrossOver"), selection: crossOverStatus) {
                    ForEach(CrossOverCompatibility.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("gameCompatibility.crossOverPicker")

                Toggle(L10n.string("GPTK 4 (Beta 2)"), isOn: gptk4BetaEnabled)
                    .toggleStyle(.switch)
                    .disabled(OSVersion < 27)
                    .help(L10n.string("Requires macOS 27 or later"))
                    .accessibilityIdentifier("gameCompatibility.gptk4Toggle")

                if crossOverStatus.wrappedValue == .supported {
                    CrossOverMacRequirementsEditor(game: game)
                }
            }
            .controlSize(.small)
        }
    }

    private var crossOverStatus: Binding<CrossOverCompatibility> {
        Binding(
            get: {
                compatibilityStore.profile(for: game).crossOverStatus
            },
            set: { status in
                compatibilityStore.setCrossOverStatus(status, for: game)
            }
        )
    }

    private var gptk4BetaEnabled: Binding<Bool> {
        Binding(
            get: {
                compatibilityStore.profile(for: game).gptk4BetaEnabled
            },
            set: { isEnabled in
                compatibilityStore.setGPTK4BetaEnabled(isEnabled, for: game)
            }
        )
    }
}

private struct CrossOverMacRequirementsEditor: View {
    let game: Game

    @EnvironmentObject private var compatibilityStore: GameCompatibilityStore
    @State private var minimum = ""
    @State private var recommended = ""
    @State private var hasLoadedRequirements = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text(L10n.string("CrossOver macOS Requirements"))
                .font(.subheadline.weight(.semibold))

            requirementEditor(
                title: L10n.string("Minimum:"),
                text: $minimum,
                accessibilityIdentifier: "gameCompatibility.crossOverMinimumRequirements"
            )

            requirementEditor(
                title: L10n.string("Recommended:"),
                text: $recommended,
                accessibilityIdentifier: "gameCompatibility.crossOverRecommendedRequirements"
            )

            if compatibilityStore.profile(for: game).crossOverMacRequirements != nil {
                Button(L10n.string("Clear Requirements"), role: .destructive) {
                    minimum = ""
                    recommended = ""
                    compatibilityStore.clearCrossOverMacRequirements(for: game)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("gameCompatibility.clearCrossOverRequirements")
            }
        }
        .onAppear(perform: loadRequirements)
        .onChange(of: minimum) { _, _ in persistRequirements() }
        .onChange(of: recommended) { _, _ in persistRequirements() }
    }

    private func requirementEditor(
        title: String,
        text: Binding<String>,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(minHeight: 54, maxHeight: 90)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.12))
                }
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private func loadRequirements() {
        let requirements = compatibilityStore.profile(for: game).crossOverMacRequirements
        minimum = requirements?.minimum ?? ""
        recommended = requirements?.recommended ?? ""
        hasLoadedRequirements = true
    }

    private func persistRequirements() {
        guard hasLoadedRequirements else { return }
        compatibilityStore.updateCrossOverMacRequirements(
            minimum: minimum,
            recommended: recommended,
            for: game
        )
    }
}
