//
//  SteamMetadataLinkEditor.swift
//  Procyon
//

import SwiftUI
import Kingfisher

struct SteamMetadataLinkEditor: View {
    @Binding var input: String
    @Binding var selectedFields: Set<SteamMetadataField>

    let currentLink: SteamMetadataLink?
    let preview: SteamGame?
    let isLoading: Bool
    let message: String?
    let previewAction: () -> Void
    let applyAction: () -> Void
    let unlinkAction: () -> Void

    var body: some View {
        GroupBox(L10n.string("Steam Metadata Link")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    L10n.string(
                        "Link a native game to a confirmed Steam app for display metadata. Its native launch identity will not change."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        L10n.string("Steam App ID or Store URL"),
                        text: $input
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("steamMetadata.input")

                    Button(action: previewAction) {
                        Label(
                            L10n.string("Preview Steam Metadata"),
                            systemImage: "magnifyingglass"
                        )
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .accessibilityIdentifier("steamMetadata.preview")

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let preview {
                    HStack(alignment: .top, spacing: 12) {
                        KFImage(URL(string: preview.headerImage))
                            .placeholder { ProgressView() }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 70)
                            .clipped()
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(preview.name)
                                .font(.headline)
                            Text(L10n.format("Steam App ID: %@", String(preview.steamAppID)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let developers = preview.developers, !developers.isEmpty {
                                Text(developers.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }

                    Text(L10n.string("Use these Steam fields:"))
                        .font(.subheadline.weight(.semibold))

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(SteamMetadataField.allCases, id: \.self) { field in
                            Toggle(field.title, isOn: fieldBinding(field))
                                .toggleStyle(.checkbox)
                        }
                    }

                    HStack {
                        Button(action: applyAction) {
                            Label(
                                currentLink == nil
                                    ? L10n.string("Link Steam Metadata")
                                    : L10n.string("Update Steam Metadata Link"),
                                systemImage: "link"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedFields.isEmpty)
                        .accessibilityIdentifier("steamMetadata.apply")

                        if currentLink != nil {
                            Button(
                                L10n.string("Unlink Steam Metadata"),
                                role: .destructive,
                                action: unlinkAction
                            )
                            .accessibilityIdentifier("steamMetadata.unlink")
                        }
                    }
                } else if let currentLink {
                    HStack {
                        Text(
                            L10n.format(
                                "Linked to Steam App %@ (%@).",
                                String(currentLink.appID),
                                currentLink.confirmedStoreName
                            )
                        )
                        .font(.footnote)

                        Button(
                            L10n.string("Unlink Steam Metadata"),
                            role: .destructive,
                            action: unlinkAction
                        )
                        .accessibilityIdentifier("steamMetadata.unlink")
                    }
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func fieldBinding(_ field: SteamMetadataField) -> Binding<Bool> {
        Binding(
            get: { selectedFields.contains(field) },
            set: { isSelected in
                if isSelected {
                    selectedFields.insert(field)
                } else {
                    selectedFields.remove(field)
                }
            }
        )
    }
}
