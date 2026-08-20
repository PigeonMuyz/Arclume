//
//  NativeGameImportView.swift
//  Procyon
//

import SwiftUI
import AppKit

struct NativeGameImportView: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var libraryPageGlobals: LibraryPageGlobals
    @State private var candidates: [NativeGameApplication] = []
    @State private var selectedIDs = Set<String>()
    @State private var isScanning = true

    private var selectedApplications: [NativeGameApplication] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        Modal(
            L10n.string("Import Native Games"),
            showModal: $isPresented,
            scrollable: false
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.string("Select apps to add to your native library."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        scan()
                    } label: {
                        Label(L10n.string("Rescan"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isScanning)
                }

                Group {
                    if isScanning {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(L10n.string("Scanning native games…"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if candidates.isEmpty {
                        ContentUnavailableView {
                            Label(
                                L10n.string("No native games found"),
                                systemImage: "gamecontroller"
                            )
                        } description: {
                            Text(L10n.string(
                                "No Apps declaring the Games category were found in /Applications or ~/Applications."
                            ))
                        }
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(candidates) { application in
                                    Toggle(isOn: selectionBinding(for: application)) {
                                        HStack(spacing: 12) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                                                .resizable()
                                                .interpolation(.high)
                                                .scaledToFit()
                                                .frame(width: 38, height: 38)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(application.name)
                                                    .lineLimit(1)
                                                Text(application.url.path)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .padding(10)
                                    .background(.black.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(height: 320)

                Divider()

                HStack {
                    Button(L10n.string("Cancel")) {
                        isPresented = false
                    }
                    Spacer()
                    Button(
                        L10n.format(
                            "Import Selected (%@)",
                            String(selectedApplications.count)
                        )
                    ) {
                        libraryPageGlobals.importNativeGameApplications(selectedApplications)
                        Task { await libraryPageGlobals.refreshNativeAppStoreMetadata() }
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning || selectedApplications.isEmpty)
                }
            }
            .frame(width: 620)
            .padding(.vertical)
        }
        .task {
            scan()
        }
    }

    private func selectionBinding(for application: NativeGameApplication) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(application.id) },
            set: { isSelected in
                if isSelected {
                    selectedIDs.insert(application.id)
                } else {
                    selectedIDs.remove(application.id)
                }
            }
        )
    }

    private func scan() {
        isScanning = true
        Task {
            let discoveredApplications = await Task.detached(priority: .userInitiated) {
                NativeGameScanner.scanStandardLocations()
            }.value

            libraryPageGlobals.refreshNativeGameApplicationImports(
                with: discoveredApplications
            )
            candidates = discoveredApplications.filter {
                !libraryPageGlobals.isNativeGameApplicationImported($0)
            }
            selectedIDs = Set(candidates.map(\.id))
            isScanning = false
        }
    }
}

#Preview {
    @Previewable @State var isPresented = true
    NativeGameImportView(isPresented: $isPresented)
        .environmentObject(LibraryPageGlobals())
}
