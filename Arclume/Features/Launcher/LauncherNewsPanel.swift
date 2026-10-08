import SwiftUI
import Kingfisher

/// The artwork meets the list edge; only individual announcement rows are inset.
struct LauncherNewsPanel: View {
    let feed: JX3LauncherFeed
    let onSelect: (LauncherNewsItem) -> Void
    @State private var selectedSlide = 0
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slides: [JX3LauncherArticle] { feed.carousel.filter { $0.thumbnailURL != nil } }
    private var entries: [LauncherNewsItem] {
        // Preserve the source's ordering within each kind; do not lose notices behind a tab.
        var seen = Set<String>()
        return (feed.notices.map(LauncherNewsItem.init(notice:)) + feed.news.map(LauncherNewsItem.init(article:)))
            .filter { seen.insert($0.safeSourceURL?.absoluteString ?? $0.id).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !slides.isEmpty { carousel }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entries) { entry in
                        LauncherNewsRow(item: entry) { onSelect(entry) }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: slides.map(\.id)) {
            selectedSlide = 0
            guard slides.count > 1 else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                guard !isHovering, !reduceMotion else { continue }
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedSlide = (selectedSlide + 1) % slides.count
                }
            }
        }
    }

    private var carousel: some View {
        GeometryReader { geometry in
            let index = min(selectedSlide, slides.count - 1)
            let slide = slides[index]
            Button { onSelect(LauncherNewsItem(article: slide)) } label: {
                KFImage(slide.thumbnailURL)
                    .placeholder { Rectangle().fill(.white.opacity(0.08)) }
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(slide.title)
            .help(slide.title)
            .id(slide.id)
            .overlay(alignment: .bottomTrailing) {
                if slides.count > 1 {
                    HStack(spacing: 2) {
                        ForEach(Array(slides.enumerated()), id: \.element.id) { offset, item in
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selectedSlide = offset }
                            } label: {
                                Circle().fill(.white.opacity(offset == index ? 1 : 0.45))
                                    .frame(width: 7, height: 7).padding(3)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("切换至第 \(offset + 1) 张：\(item.title)")
                            .accessibilityAddTraits(offset == index ? .isSelected : [])
                        }
                    }
                    .padding(3)
                    .background(.black.opacity(0.25), in: Capsule())
                    .padding(8)
                }
            }
        }
        .aspectRatio(304.0 / 143, contentMode: .fit)
        .onHover { isHovering = $0 }
    }
}

private struct LauncherNewsRow: View {
    let item: LauncherNewsItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 12))
                        .lineLimit(1).truncationMode(.tail)
                    if let date = item.date, !date.isEmpty {
                        Text(date).font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 63, alignment: .leading)
            .background(.primary.opacity(hovering ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(item.title)
        .accessibilityHint("打开正文")
    }
}
