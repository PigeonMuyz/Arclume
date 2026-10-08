import SwiftUI
import Kingfisher

struct GameDBMetadataView: View {
    let game: Game
    @EnvironmentObject private var library: LibraryPageGlobals
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GameDBSearchResult] = []
    @State private var preview: GameDBMetadata?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("补全游戏资料").font(.title2)
            Text("来源：LizardByte GameDB / IGDB。仅填补空白资料，不改变启动路径或覆盖手工编辑。")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                TextField("游戏名称（建议使用英文原名）", text: $query)
                Button("搜索") { search() }.disabled(busy || query.isEmpty)
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { result in
                        Button("\(result.name) · #\(result.id)") {
                            busy = true; error = nil
                            Task {
                                defer { busy = false }
                                do { preview = try await GameDBMetadataService.shared.details(id: result.id) }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(busy)
                    }
                    if let preview {
                        Divider()
                        HStack(alignment: .top) {
                            KFImage(URL(string: GameDBMetadataService.artworkURL(preview.cover) ?? ""))
                                .resizable().scaledToFit().frame(width: 110, height: 155)
                            VStack(alignment: .leading) {
                                Text(preview.name).font(.headline)
                                Text(preview.summary ?? "暂无简介").font(.caption)
                            }
                        }
                    }
                }
            }.frame(minHeight: 180, maxHeight: 340)
            HStack {
                Button("关闭") { dismiss() }
                if game.gameDBLink != nil {
                    Button("解除资料关联") { library.setGameDBMetadata(nil, for: game.id); dismiss() }
                }
                Spacer()
                Button("确认关联并同步") {
                    if let preview { library.setGameDBMetadata(preview, for: game.id); dismiss() }
                }.disabled(preview == nil || busy).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 590)
        .onAppear {
            query = game.gameDBLink?.metadata.name ?? (game.appExeURL.map(WindowsGameLaunchRules.isEndfield) == true ? "Arknights: Endfield" : game.name)
            preview = game.gameDBLink?.metadata
        }
    }

    private func search() {
        busy = true; error = nil; preview = nil
        Task {
            defer { busy = false }
            do {
                results = try await GameDBMetadataService.shared.search(query)
                if results.isEmpty { error = "没有匹配结果，请尝试完整英文游戏名。" }
            } catch { self.error = error.localizedDescription }
        }
    }
}
