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
    var onStopContainer: (@MainActor () -> Void)? = nil
    var stopConfirmationMessage = "将结束 Arclume Wine 容器中的 Windows 程序，未保存内容可能丢失。不会结束其他容器，也不会删除游戏、缓存或账户数据。"
    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var windowsInstallerStore: WindowsInstallerStore
    @State private var confirmStopContainer = false

    var body: some View {
        HStack(spacing: 8) {
            if let onStopContainer {
                Button {
                    confirmStopContainer = true
                } label: {
                    Label {
                        Text(libraryPageGlobals.isStoppingWine ? "正在结束容器…" : "强制结束容器运行")
                    } icon: {
                        if libraryPageGlobals.isStoppingWine {
                            ProgressView().controlSize(.small).frame(width: 24, height: 24)
                        } else if compactIcons {
                            LauncherToolbarIcon(symbol: "exclamationmark.octagon")
                        } else {
                            Image(systemName: "exclamationmark.octagon")
                        }
                    }
                }
                .disabled(libraryPageGlobals.isStoppingWine)
                .accessibilityLabel(libraryPageGlobals.isStoppingWine ? "正在结束 Arclume Wine" : "强制结束容器运行")
                .accessibilityIdentifier("stop-wine-button")
                .help("按当前运行时停止 Windows 程序")
                .confirmationDialog("强制结束容器运行？", isPresented: $confirmStopContainer, titleVisibility: .visible) {
                    Button("结束容器运行", role: .destructive) { onStopContainer() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(stopConfirmationMessage)
                }
            }
            Menu {
                Button("安装 Windows 程序…", systemImage: "shippingbox.and.arrow.backward") {
                    libraryPageGlobals.showWindowsInstaller = true
                }
                Button("添加已安装游戏…", systemImage: "gamecontroller") {
                    libraryPageGlobals.openCustomGameEditor()
                }
            } label: {
                actionLabel(windowsInstallerStore.busy ? "正在安装…" : "添加游戏程序", symbol: "plus")
            }
            .menuIndicator(compactIcons ? .hidden : .automatic)
            .accessibilityIdentifier("library-add-game-button")
            .launcherTourTarget(.add)
            .help("添加游戏程序或安装 Windows 程序")

            Button {
                if let bottle = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle) {
                    showFolder(url: bottle)
                }
            } label: {
                actionLabel("打开容器目录", symbol: "folder")
            }
            .disabled(OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle) == nil)
            .accessibilityIdentifier("library-open-container-folder-button")
            .help("在 Finder 中打开当前容器目录")

            Button {
                presentTools()
            } label: {
                actionLabel("拓展工具", symbol: "wrench.and.screwdriver")
            }
            .accessibilityIdentifier("library-tools-button")
            .help("拓展工具")
        }
    }

    @ViewBuilder private func actionLabel(_ title: String, symbol: String) -> some View {
        if compactIcons {
            Label { Text(title) } icon: { LauncherToolbarIcon(symbol: symbol) }
        } else {
            Label(title, systemImage: symbol)
        }
    }

    @MainActor
    private func presentTools() {
        libraryPageGlobals.showTools = false
        DispatchQueue.main.async {
            libraryPageGlobals.showTools = true
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
