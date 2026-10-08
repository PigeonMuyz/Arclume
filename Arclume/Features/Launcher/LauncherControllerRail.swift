import SwiftUI

/// The connected-controller layout shares selection and order with the mouse sidebar.
struct LauncherControllerRail: View {
    let games: [Game]
    let selectedID: String?
    let onSelect: (String) -> Void
    let onMove: (String, LauncherSidebarInsertion) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredID: String?
    @State private var frames: [String: CGRect] = [:]
    @State private var insertion: LauncherSidebarInsertion?
    @State private var sourceID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LB / RB  切换游戏")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(games) { game in
                            gameButton(game)
                                .id(game.id)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .frame(height: 74)
                .glassEffect(in: .rect(cornerRadius: 22))
                .onChange(of: selectedID, initial: true) { _, id in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .coordinateSpace(name: "launcher.controllerRail")
        .onPreferenceChange(LauncherSidebarFrames.self) { frames = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hoveredID)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: games.map(\.id))
        .accessibilityIdentifier("launcher.controllerRail")
    }

    private func gameButton(_ game: Game) -> some View {
        Button { onSelect(game.id) } label: {
            LauncherApplicationIcon(game: game, size: 46)
                .scaleEffect(!reduceMotion && hoveredID == game.id ? 1.08 : 1)
                .frame(width: 58, height: 58)
                .background(selectedID == game.id ? Color.accentColor.opacity(0.4) : Color.white.opacity(hoveredID == game.id ? 0.12 : 0), in: .rect(cornerRadius: 14))
                .overlay {
                    if selectedID == game.id {
                        RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help(game.name)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(selectedID == game.id ? [.isSelected] : [])
        .onHover { hoveredID = $0 ? game.id : nil }
        .opacity(sourceID == game.id ? 0.4 : 1)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: LauncherSidebarFrames.self,
                    value: [game.id: geometry.frame(in: .named("launcher.controllerRail"))])
            }
        }
        .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("launcher.controllerRail"))
            .onChanged { value in
                sourceID = game.id
                insertion = LauncherSidebarInsertion.target(at: value.location, source: game.id, frames: frames, horizontal: true)
            }
            .onEnded { value in
                let destination = LauncherSidebarInsertion.target(at: value.location, source: game.id, frames: frames, horizontal: true)
                sourceID = nil
                insertion = nil
                if let destination { onMove(game.id, destination) }
            })
        .overlay(alignment: insertion?.after == true ? .trailing : .leading) {
            if insertion?.target == game.id {
                Capsule().fill(.white).frame(width: 3, height: 44)
                    .offset(x: insertion?.after == true ? 5 : -5)
                    .allowsHitTesting(false)
            }
        }
    }
}
