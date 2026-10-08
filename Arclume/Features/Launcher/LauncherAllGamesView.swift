import SwiftUI

/// A transient library picker. Selection never launches or installs a game.
struct LauncherAllGamesView: View {
    let games: [Game]
    let onSelect: (Game) -> Void
    let onClose: () -> Void
    @State private var query = ""
    @State private var hoveredID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    private var results: [Game] {
        LauncherGameCatalog.filtered(games, query: query)
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索游戏或应用", text: $query)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .accessibilityIdentifier("all-games.search")
                        .onSubmit { if let game = results.first { choose(game) } }
                    if !query.isEmpty {
                        Button("清除搜索", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: 290)
                .background(.quaternary, in: Capsule())
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                    .buttonStyle(.glass).controlSize(.large)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.cancelAction)
                    .help("关闭").accessibilityLabel("关闭")
                    .accessibilityIdentifier("all-games.close")
            }
            if results.isEmpty {
                ContentUnavailableView(query.isEmpty ? "暂无游戏" : "没有匹配的游戏",
                    systemImage: query.isEmpty ? "gamecontroller" : "magnifyingglass",
                    description: Text(query.isEmpty ? "通过右上角添加游戏或应用。" : "试试其他名称。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 18)], spacing: 24) {
                        ForEach(results) { game in
                            Button { choose(game) } label: {
                                VStack(spacing: 12) {
                                    LauncherApplicationIcon(game: game, size: 72)
                                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                                        .scaleEffect(!reduceMotion && hoveredID == game.id ? 1.06 : 1)
                                        .brightness(hoveredID == game.id ? 0.06 : 0)
                                    Text(game.name).font(.body.weight(.medium)).lineLimit(1)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 22, alignment: .top)
                                }
                                .padding(10).frame(maxWidth: .infinity)
                                .background(hoveredID == game.id ? Color.primary.opacity(0.10) : .clear,
                                            in: .rect(cornerRadius: 14))
                                .contentShape(.rect(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering { hoveredID = game.id }
                                else if hoveredID == game.id { hoveredID = nil }
                            }
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hoveredID == game.id)
                            .help(game.name)
                            .accessibilityLabel(game.name)
                            .accessibilityIdentifier("all-games.item.\(game.id)")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 10)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { searchFocused = true }
        .onExitCommand { onClose() }
    }

    private func choose(_ game: Game) {
        onSelect(game)
        onClose()
    }

}
