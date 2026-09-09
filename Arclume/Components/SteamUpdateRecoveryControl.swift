import SwiftUI

struct SteamUpdateRecoveryControl: View {
    @EnvironmentObject private var store: ContainerSteamStore
    @EnvironmentObject private var library: LibraryPageGlobals
    @State private var confirm = false
    @State private var failure: String?

    var body: some View {
        Group {
            if store.steamNeedsRecovery {
            Button("重新启动 Steam", systemImage: "arrow.clockwise.circle") { confirm = true }
                .tint(.orange)
                .disabled(store.steamOpening || library.isStoppingWine)
                .help("检测到 Steam 更新完成，但旧进程未退出")
                .confirmationDialog("重新启动 Steam？", isPresented: $confirm) {
                    Button("结束 Steam 容器进程并重新启动", role: .destructive) {
                        store.recoverSteamAfterUpdate { failure = $0 }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("将结束 Steam 容器中的 Windows 程序，未保存的内容可能丢失。不会结束剑三 Games 容器，也不会删除游戏、缓存或账户数据。")
                }
            }
        }
        .alert("无法重新启动 Steam", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("好", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }
}
