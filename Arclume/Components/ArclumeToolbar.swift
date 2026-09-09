import SwiftUI

struct ArclumeToolbar: View {
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var containerSteamStore: ContainerSteamStore
    @EnvironmentObject var windowsInstallerStore: WindowsInstallerStore
    @State private var steamLaunchError: String?

    var body: some View {
        HStack(spacing: 8) {
            if containerSteamStore.isReady {
                SteamUpdateRecoveryControl()
                Button {
                    containerSteamStore.openSteam(using: .bundledWine) { steamLaunchError = $0 }
                } label: {
                    Label {
                        Text(containerSteamStore.steamOpening ? "准备 Steam…" : "打开 Steam")
                    } icon: {
                        Image("steam-fill").resizable().scaledToFit().frame(width: 16, height: 16)
                    }
                }
                .disabled(libraryPageGlobals.isStoppingWine || containerSteamStore.steamOpening)
                .accessibilityIdentifier("library-open-steam-button")
                .help("打开当前 Windows 游戏容器中的 Steam")
            }
            Menu {
                Button("安装 Windows 程序…", systemImage: "shippingbox.and.arrow.backward") {
                    libraryPageGlobals.showWindowsInstaller = true
                }
                Button("添加已安装游戏…", systemImage: "gamecontroller") {
                    libraryPageGlobals.openCustomGameEditor()
                }
            } label: {
                Label(windowsInstallerStore.busy ? "正在安装…" : "添加游戏", systemImage: "plus")
            }
            .accessibilityIdentifier("library-add-game-button")

            Menu {
                if let bottle = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle) {
                    Button("打开容器文件夹") { showFolder(url: bottle) }
                }
                Button("管理运行时与容器…") {
                    libraryPageGlobals.requestedSettingsPage = "运行时"
                    libraryPageGlobals.showOptions = true
                }
            } label: {
                Label("容器", systemImage: "shippingbox")
            }

            Button {
                libraryPageGlobals.showTools = true
            } label: {
                Label("工具", systemImage: "wrench.and.screwdriver")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .alert("无法打开 Steam", isPresented: Binding(
            get: { steamLaunchError != nil },
            set: { if !$0 { steamLaunchError = nil } }
        )) {
            Button("好", role: .cancel) { steamLaunchError = nil }
        } message: {
            Text(steamLaunchError ?? "")
        }
    }
}
