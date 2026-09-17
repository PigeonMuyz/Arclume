import SwiftUI

/// A full-window presentation of the shared library, not a separate runtime mode.
struct LauncherLibraryView: View {
    @EnvironmentObject private var library: LibraryPageGlobals
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("launcher.gameOrder.v1", store: UserDefaults(suiteName: suiteName)) private var savedOrder = "[]"
    @AppStorage("launcher.sidebarExpanded", store: UserDefaults(suiteName: suiteName)) private var expanded = true
    @SceneStorage("launcher.selectedGameID") private var selectionID = ""
    @State private var hoveredGameID: String?
    @State private var insertion: LauncherSidebarInsertion?
    @State private var drag: LauncherSidebarDrag?
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var showAllGames = false
    @Binding var selectedTitle: String
    let onLaunchJX3: (Game) -> Void
    let onStopJX3: () -> Void
    private let sidebarWidth: CGFloat = 74

    private var orderedIDs: [String] {
        LauncherLibraryOrder.reconciled(saved: LauncherLibraryOrder.decode(savedOrder), available: library.allGames.map(\.id))
    }

    private var games: [Game] {
        // This presentation has no search/filter controls; never inherit a hidden grid query.
        let visible = library.allGames.filter(\.isInstalled)
        let ranks = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })
        return visible.sorted { ranks[$0.id, default: .max] < ranks[$1.id, default: .max] }
    }

    private var selection: Game? { games.first { $0.id == selectionID } ?? games.first }

    private var catalogGames: [Game] {
        let byID = Dictionary(library.allGames.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return orderedIDs.compactMap { byID[$0] }
    }

    var body: some View {
        GlassEffectContainer(spacing: 16) {
        ZStack(alignment: .leading) {
            if let game = selection {
                LauncherGameHomeView(game: game, onLaunchJX3: { onLaunchJX3(game) }, onStopJX3: onStopJX3)
                    .id(game.id)
            } else {
                ContentUnavailableView("还没有已安装的游戏", systemImage: "gamecontroller", description: Text("从右上角的添加按钮添加游戏。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 8) {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(games) { game in
                                Button { selectionID = game.id } label: {
                                    LauncherApplicationIcon(game: game, size: 46)
                                        .scaleEffect(!reduceMotion && hoveredGameID == game.id ? 1.08 : 1)
                                        .brightness(hoveredGameID == game.id ? 0.07 : 0)
                                        .shadow(color: .white.opacity(hoveredGameID == game.id ? 0.3 : 0), radius: 7)
                                        .frame(width: 58, height: 58)
                                        .background(selection?.id == game.id ? Color.accentColor.opacity(0.4) : Color.white.opacity(hoveredGameID == game.id ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 14))
                                        .overlay {
                                            if selection?.id == game.id {
                                                RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                                            }
                                        }
                                        .contentShape(RoundedRectangle(cornerRadius: 14))
                                        .offset(y: reduceMotion || insertion?.target != game.id ? 0 : insertion?.after == true ? -3 : 3)
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    if hovering { hoveredGameID = game.id }
                                    else if hoveredGameID == game.id { hoveredGameID = nil }
                                }
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hoveredGameID == game.id)
                                .help(game.name)
                                .accessibilityLabel(game.name)
                                .accessibilityAddTraits(selection?.id == game.id ? [.isSelected] : [])
                                .opacity(drag?.source == game.id ? 0.35 : 1)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(key: LauncherSidebarFrames.self,
                                            value: [game.id: geometry.frame(in: .named("launcher.sidebar"))])
                                    }
                                }
                                .highPriorityGesture(reorderGesture(for: game.id))
                                .overlay(alignment: insertion?.after == true ? .bottom : .top) {
                                    if insertion?.target == game.id {
                                        Capsule().fill(.white).frame(height: 3)
                                            .shadow(color: .black.opacity(0.45), radius: 2)
                                            .offset(y: insertion?.after == true ? 5 : -5)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: insertion)
                                .contextMenu {
                                    Button("移到最前") {
                                        guard let first = orderedIDs.first else { return }
                                        savedOrder = LauncherLibraryOrder.encode(LauncherLibraryOrder.moving(game.id, before: first, in: orderedIDs))
                                    }
                                    Button("移到最后") {
                                        savedOrder = LauncherLibraryOrder.encode(orderedIDs.filter { $0 != game.id } + [game.id])
                                    }
                                }
                            }
                        }.padding(8)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: games.map(\.id))
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: sidebarWidth)
                    .glassEffect(in: .rect(cornerRadius: 22))
                    .padding(.top, 72)
                    .padding(.bottom, 122)
                    // Keep the glass rail mounted: animate its actual position instead
                    // of relying on insertion/removal of a lazy scroll view.
                    .offset(x: expanded || reduceMotion ? 0 : -(sidebarWidth + 28))
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.35), value: expanded)
            }
            .padding(.leading, 14)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(spacing: 8) {
                Button {
                    showAllGames.toggle()
                } label: {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(.glass).controlSize(.large)
                .help("全部游戏（⌘F）")
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("全部游戏")
                .accessibilityIdentifier("launcher.all-games")
            Button {
                hoveredGameID = nil
                insertion = nil
                drag = nil
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.left" : "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .help(expanded ? "收起游戏列表" : "展开游戏列表")
            .accessibilityLabel(expanded ? "收起游戏列表" : "展开游戏列表")
            .accessibilityIdentifier("launcher.toggleSidebar")
            }
            .frame(width: sidebarWidth)
            .padding(.leading, 14)
            .padding(.bottom, 18)
        }
        }
        .allowsHitTesting(!showAllGames)
        .accessibilityHidden(showAllGames)
        // A drag preview floats above the completed glass composition. Placing
        // it inside GlassEffectContainer lets the rail's glass cover the icon.
        .overlay(alignment: .topLeading) {
            if let drag, let game = games.first(where: { $0.id == drag.source }) {
                LauncherApplicationIcon(game: game, size: 46)
                    .frame(width: 58, height: 58)
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
                    .shadow(radius: 6, y: 3)
                    .position(drag.location)
                    .zIndex(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .coordinateSpace(name: "launcher.sidebar")
        .onPreferenceChange(LauncherSidebarFrames.self) { rowFrames = $0 }
        .overlay {
            if showAllGames {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.22)
                            .contentShape(Rectangle())
                            .onTapGesture { showAllGames = false }
                            .accessibilityHidden(true)
                        LauncherAllGamesView(games: catalogGames, onSelect: { game in
                            selectionID = game.id
                        }, onClose: { showAllGames = false })
                        .frame(width: min(1040, max(0, geometry.size.width - 64)),
                               height: max(0, geometry.size.height - 48))
                        .background(.regularMaterial, in: .rect(cornerRadius: 28))
                        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.14)) }
                        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showAllGames)
        .onChange(of: selection?.name, initial: true) { _, name in selectedTitle = name ?? "Arclume" }
        .onChange(of: games.map(\.id), initial: true) { _, ids in
            if !ids.contains(selectionID) { selectionID = games.first?.id ?? ids.first ?? "" }
            if let drag, !ids.contains(drag.source) { self.drag = nil; insertion = nil }
        }
    }

    private func reorderGesture(for source: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("launcher.sidebar"))
            .onChanged { value in
                drag = LauncherSidebarDrag(source: source, location: value.location)
                insertion = LauncherSidebarInsertion.target(at: value.location, source: source, frames: rowFrames)
            }
            .onEnded { value in
                let destination = LauncherSidebarInsertion.target(at: value.location, source: source, frames: rowFrames)
                drag = nil
                insertion = nil
                guard let destination else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                    savedOrder = LauncherLibraryOrder.encode(LauncherLibraryOrder.moving(source,
                        relativeTo: destination.target, after: destination.after, in: orderedIDs))
                }
            }
    }
}
