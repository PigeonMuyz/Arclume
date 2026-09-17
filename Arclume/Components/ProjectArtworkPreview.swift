import SwiftUI
import Kingfisher
import UniformTypeIdentifiers

/// A draft-only artwork control: choosing or clearing an image never saves a project.
struct ProjectArtworkPreview: View {
    let title: String
    @Binding var value: String
    var fallback: URL?
    var fallbackImage: NSImage? = nil
    var logo = false
    @State private var showAddress = false

    private var imageURL: URL? { value.isEmpty ? fallback : URL(string: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geometry in
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.45))
                    if value.isEmpty, let image = fallbackImage {
                        Image(nsImage: image).resizable().scaledToFit().padding(16)
                    } else if let url = imageURL {
                        if logo {
                            artwork(url).scaledToFit().padding(16)
                        } else {
                            artwork(url).scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: logo ? "textformat" : "photo").font(.title2)
                            Text(logo ? "自动使用游戏标志" : "自动获取背景").font(.caption)
                        }.foregroundStyle(.secondary)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            }.frame(height: logo ? 94 : 160)
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Menu {
                    Button("选择图片…", systemImage: "photo") { chooseImage() }
                    Button("使用图片链接…", systemImage: "link") { showAddress = true }
                    if !value.isEmpty {
                        Button("恢复自动获取", systemImage: "arrow.counterclockwise") { value = "" }
                    }
                } label: { Label("更换", systemImage: "pencil") }
                .menuStyle(.borderlessButton).fixedSize()
                .popover(isPresented: $showAddress) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(title)链接").font(.headline)
                        TextField("https://…", text: $value).textFieldStyle(.roundedBorder)
                        HStack { Spacer(); Button("完成") { showAddress = false }.buttonStyle(.glass) }
                    }.padding(20).frame(width: 340)
                }
            }
        }
    }

    private func artwork(_ url: URL) -> KFImage {
        KFImage(url).placeholder {
            Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
        }.resizable()
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "选择\(title)"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { value = url.absoluteString }
    }
}
