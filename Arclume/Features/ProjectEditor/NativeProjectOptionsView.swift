import SwiftUI

struct NativeProjectOptionsView: View {
    let game: Game
    @EnvironmentObject private var gameOptions: GameOptions
    private var key: String { namespacedKey("GameOptions", OnlineGameMode.gameOptionsIdentifier(for: game)) }

    private var metalHUD: Binding<Bool> {
        Binding(
            get: { gameOptions.mtlHudEnabled },
            set: { enabled in
                gameOptions.mtlHudEnabled = enabled
                GameOptionsPersistence.update(key: key) { $0.mtlHudEnabled = enabled }
            }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Form {
                LabeledContent("运行方式", value: "macOS 原生应用")
                Toggle("显示 Metal 性能面板", isOn: metalHUD)
                Text("在下次启动时生效。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
        }.frame(width: 460, height: 200)
        .onChange(of: key, initial: true) {
            gameOptions.set(data: GameOptionsPersistence.read(key: key))
        }
    }
}
