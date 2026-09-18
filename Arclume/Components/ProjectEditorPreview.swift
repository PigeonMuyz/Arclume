import SwiftUI

/// Scale the production composition instead of drawing a different poster card.
struct ProjectEditorPreview: View {
    let game: Game?
    let name: String
    let summary: String
    let backgroundURL: URL?
    let logoURL: URL?
    var logoImage: NSImage?
    @State private var viewport = CGSize(width: 1200, height: 720)

    private var previewGame: Game {
        var result = game ?? .emptyGame
        result.name = name.isEmpty ? "新项目" : name
        result.shortDescription = summary
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geometry in
                LauncherGameHomeView(game: previewGame, onLaunchJX3: {}, onStopJX3: {},
                    presentationOverride: ProjectPresentation(name: name, summary: summary,
                        background: backgroundURL?.absoluteString ?? "",
                        logo: logoURL?.absoluteString ?? ""), isPreview: true)
                    .frame(width: viewport.width, height: viewport.height)
                    .scaleEffect(geometry.size.width / viewport.width, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.width * viewport.height / viewport.width, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .environment(\.launcherTour, nil)
            }
            .frame(height: 400 * viewport.height / viewport.width)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Label("启动器预览", systemImage: "macwindow").font(.subheadline.weight(.medium))
            Text("仅预览当前项目的背景、标志和信息，修改保存后生效。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(height: 448)
        .background(LauncherPreviewViewport(size: $viewport))
    }
}

private struct LauncherPreviewViewport: NSViewRepresentable {
    @Binding var size: CGSize
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard var window = view?.window else { return }
            while let owner = window.sheetParent ?? window.parent { window = owner }
            let measured = window.contentLayoutRect.size
            if measured.width > measured.height, measured.height > 0, measured != size { size = measured }
        }
    }
}
