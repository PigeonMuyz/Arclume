import SwiftUI

struct ArclumeToolbar: View {
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                Label(expanded ? "收起" : "操作", systemImage: expanded ? "xmark" : "plus")
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("library-actions-toggle")
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                ArclumeLibraryActions()
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .fixedSize()
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .controlSize(.large)
    }

}

/// Shared actions, styled by their host: grid shelf or native window toolbar.
struct ArclumeLibraryActions: View {
    var compactIcons = false
    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var containerSteamStore: ContainerSteamStore
    @EnvironmentObject private var windowsInstallerStore: WindowsInstallerStore
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
                        Image("steam-fill").resizable().scaledToFit()
                            .frame(width: compactIcons ? 18 : 16, height: compactIcons ? 18 : 16)
                            .frame(width: compactIcons ? 24 : 16, height: compactIcons ? 24 : 16)
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
                actionLabel(windowsInstallerStore.busy ? "正在安装…" : "添加游戏", symbol: "plus")
            }
            .menuIndicator(compactIcons ? .hidden : .automatic)
            .accessibilityIdentifier("library-add-game-button")
            .launcherTourTarget(.add)
            .help("添加游戏或安装 Windows 程序")

            Menu {
                if let bottle = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle) {
                    Button("打开容器文件夹") { showFolder(url: bottle) }
                }
                Button("管理运行时与容器…") {
                    libraryPageGlobals.requestedSettingsPage = "运行时"
                    libraryPageGlobals.showOptions = true
                }
            } label: {
                actionLabel("容器", symbol: "shippingbox")
            }
            .menuIndicator(compactIcons ? .hidden : .automatic)
            .help("管理运行时与容器")

            Button {
                libraryPageGlobals.showTools = true
            } label: {
                actionLabel("工具", symbol: "wrench.and.screwdriver")
            }
            .help("工具")
        }
        .alert("无法打开 Steam", isPresented: Binding(
            get: { steamLaunchError != nil },
            set: { if !$0 { steamLaunchError = nil } }
        )) {
            Button("好", role: .cancel) { steamLaunchError = nil }
        } message: {
            Text(steamLaunchError ?? "")
        }
    }

    @ViewBuilder private func actionLabel(_ title: String, symbol: String) -> some View {
        if compactIcons {
            Label { Text(title) } icon: { LauncherToolbarIcon(symbol: symbol) }
        } else {
            Label(title, systemImage: symbol)
        }
    }
}

struct LauncherToolbarIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).resizable().scaledToFit()
            .frame(width: 18, height: 18).frame(width: 24, height: 24)
    }
}
