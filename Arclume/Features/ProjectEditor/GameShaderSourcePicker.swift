import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GameShaderSourcePicker: View {
    let game: Game
    let prefix: URL
    @State private var source: URL?
    @State private var errorMessage: String?

    var body: some View {
        Section("离线着色器") {
            LabeledContent("来源", value: source?.lastPathComponent ?? "游戏生成的缓存")
            HStack {
                Button("选择文件或目录…", action: choose)
                    .accessibilityIdentifier("shaders.chooseSource")
                if source != nil {
                    Button("使用游戏缓存") { save(nil) }
                }
                Button("打开着色器目录") {
                    let directory = GameMetalShaderCache.directory(prefix: prefix, gameID: game.id)
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { source = GameMetalShaderCache.externalSource(prefix: prefix, gameID: game.id) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "选择 \(game.name) 的离线着色器"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["db", "metallib"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url { save(url) }
    }

    private func save(_ url: URL?) {
        do {
            try GameMetalShaderCache.setExternalSource(url, prefix: prefix, gameID: game.id)
            source = url
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
