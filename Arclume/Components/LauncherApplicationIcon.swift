import AppKit
import SwiftUI

/// Icons never fall back to posters or wordmarks. Those are separate artwork roles.
struct LauncherApplicationIcon: View {
    let game: Game
    var size: CGFloat = 46
    @EnvironmentObject private var library: LibraryPageGlobals
    @State private var icon: NSImage?

    private var directory: URL? { library.gamesMeta.first { $0.id == game.id }?.gameURL }
    private var sourceKey: String { game.id + "|" + (game.appExeURL?.path ?? "") + "|" + (directory?.path ?? "") }

    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else {
                Image(systemName: "app.dashed").resizable().scaledToFit()
                    .foregroundStyle(.secondary).padding(8)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: sourceKey) {
            icon = nil
            let root = directory
            let native = game.isNative
            let names = game.appNames
            let explicit = GameRemovalService.target(for: game)
            let source = await Task.detached(priority: .utility) {
                LauncherIconSource.resolve(explicit: explicit, directory: root, native: native, names: names)
            }.value
            guard !Task.isCancelled, let source else { return }
            if native {
                if let iconFile = LauncherIconSource.nativeIconFile(at: source) {
                    icon = NSImage(contentsOf: iconFile)
                }
                if icon == nil, source.pathExtension.lowercased() == "app" {
                    icon = NSWorkspace.shared.icon(forFile: source.path)
                }
            } else {
                let data = await WindowsExecutableIconCache.shared.load(source)
                guard !Task.isCancelled else { return }
                icon = data.flatMap(NSImage.init(data:))
            }
            if let loaded = icon { icon = LauncherIconPresentation.normalized(loaded) }
        }
    }
}
