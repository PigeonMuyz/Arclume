import SwiftUI

struct NativeProjectOptionsView: View {
    let game: Game
    @EnvironmentObject private var gameOptions: GameOptions
    @State private var saved = false
    private var key: String { namespacedKey("GameOptions", OnlineGameMode.gameOptionsIdentifier(for: game)) }

    var body: some View {
        VStack(spacing: 20) {
            Form {
                LabeledContent("运行方式", value: "macOS 原生应用")
                Toggle("显示 Metal 性能面板", isOn: $gameOptions.mtlHudEnabled)
                Text("在下次启动时生效。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            HStack {
                if saved { Label("已保存", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                Spacer()
                Button("保存") {
                    persistUsrDefData(key: key, data: GameOptionsData(data: gameOptions))
                    saved = true
                }.buttonStyle(.glassProminent)
            }
        }.frame(width: 460, height: 200)
        .onAppear {
            if let data: GameOptionsData = readUsrDefData(key: key) { gameOptions.set(data: data) }
        }
    }
}
