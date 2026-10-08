import SwiftUI

struct GameContainerAssignmentView: View {
    let game: Game
    @StateObject private var store = ManagedWineContainerStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("启动容器", selection: .constant(currentID ?? "unmanaged")) {
                if currentID == nil { Text(game.installedBottleURL?.lastPathComponent ?? "未指定").tag("unmanaged") }
                ForEach(store.containers) { Text($0.name).tag($0.id) }
            }
            .disabled(!GameContainerAssignmentPolicy.isEnabled)
            .accessibilityIdentifier("game-container-assignment")
            Label("暂未开放 · 等待游戏迁移适配", systemImage: "lock")
                .font(.footnote).foregroundStyle(.secondary)
        }.onAppear { store.refresh() }
    }

    private var currentID: String? {
        GameContainerAssignmentPolicy.containerID(for: game, in: store.containers, root: store.repository.root)
    }
}
