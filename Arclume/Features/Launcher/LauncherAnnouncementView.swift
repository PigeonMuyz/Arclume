import SwiftUI

/// Matches the edited Sketch reader: fixed header, inset scrolling body, no footer.
struct LauncherAnnouncementView: View {
    let item: LauncherNewsItem
    var previewMarkdown: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var readerHTML: String?
    @State private var errorMessage: String?
    @State private var attempt = 0
    @State private var isFindVisible = false
    @State private var findQuery = ""
    @State private var findRequest: AnnouncementFindRequest?
    @State private var matchFound: Bool?
    @FocusState private var isFindFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.kind).font(.system(size: 12)).foregroundStyle(linkColor)
                    Text(item.title).font(.system(size: 22, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text([item.date, "剑网3官网"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if let url = item.safeSourceURL {
                        Button { openURL(url) } label: {
                            Label("查看原文", systemImage: "arrow.up.right")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain).foregroundStyle(linkColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    isFindVisible = true
                    isFindFocused = true
                } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                        .frame(width: 25, height: 20).contentShape(Capsule())
                }
                .buttonStyle(.glass).buttonBorderShape(.capsule)
                .keyboardShortcut("f", modifiers: .command)
                .disabled(readerHTML == nil)
                .help("查找正文（⌘F）").accessibilityLabel("查找正文")
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 25, height: 20).contentShape(Capsule())
                }
                .buttonStyle(.glass).buttonBorderShape(.capsule)
                .help("关闭")
                .accessibilityLabel("关闭公告")
            }
            if isFindVisible { findBar }
            readerBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.1)) }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 18)
        .frame(width: 820, height: 620)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        .presentationBackground(.clear)
        .interactiveDismissDisabled(isFindVisible)
        .onExitCommand {
            if isFindVisible { closeFind() } else { dismiss() }
        }
        .task(id: attempt) { await load() }
        .task(id: findQuery) {
            guard isFindVisible else { return }
            matchFound = nil
            let previousRequestID = findRequest?.id
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard isFindVisible, findRequest?.id == previousRequestID else { return }
            find()
        }
        .environment(\.openURL, OpenURLAction { url in
            guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? ""),
                  url.user == nil, url.password == nil else { return .discarded }
            return .systemAction
        })
    }

    @ViewBuilder private var readerBody: some View {
        if let readerHTML {
            AnnouncementReaderBody(html: readerHTML, findRequest: findRequest, onFindResult: { id, found in
                guard findRequest?.id == id, findRequest?.query == findQuery,
                      isFindVisible, !findQuery.isEmpty else { return }
                matchFound = found
            }, onOpenURL: { openURL($0) })
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if let errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                Text(errorMessage).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("重试") { attempt += 1 }.buttonStyle(.glass)
            }.padding(24)
        } else {
            ProgressView("正在加载正文…").controlSize(.small)
        }
    }

    private var findBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("查找正文", text: $findQuery)
                .textFieldStyle(.plain)
                .focused($isFindFocused)
                .onSubmit { find() }
                .accessibilityIdentifier("announcement-find-field")
            if matchFound == false, !findQuery.isEmpty {
                Text("未找到").font(.caption).foregroundStyle(.secondary)
            }
            Button { find(backwards: true) } label: {
                Image(systemName: "chevron.up").frame(width: 18, height: 18)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(findQuery.isEmpty)
            .help("上一个（⇧⌘G）").accessibilityLabel("上一个匹配")
            Button { find() } label: {
                Image(systemName: "chevron.down").frame(width: 18, height: 18)
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(findQuery.isEmpty)
            .help("下一个（⌘G）").accessibilityLabel("下一个匹配")
            Button("完成", action: closeFind)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func find(backwards: Bool = false) {
        matchFound = nil
        findRequest = AnnouncementFindRequest(query: findQuery, backwards: backwards)
    }

    private func closeFind() {
        isFindVisible = false
        isFindFocused = false
        findQuery = ""
        matchFound = nil
        findRequest = AnnouncementFindRequest(query: "")
    }

    private var linkColor: Color {
        colorScheme == .dark ? Color(red: 0.67, green: 0.79, blue: 1) : Color(red: 0.19, green: 0.37, blue: 0.74)
    }

    private func load() async {
        readerHTML = nil
        errorMessage = nil
        do {
            let html: String
            if let previewMarkdown {
                html = try await ArticleReaderDocument.prepare(markdown: previewMarkdown)
            } else if let url = item.safeSourceURL {
                html = try await JX3ArticleContentService.load(from: url).readerHTML
            } else {
                errorMessage = "这篇文章暂时没有正文地址。"
                return
            }
            try Task.checkCancellation()
            readerHTML = html
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
