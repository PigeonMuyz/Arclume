import SwiftUI
import WebKit

struct AnnouncementFindRequest: Equatable {
    let id = UUID()
    let query: String
    var backwards = false
}

/// Only the scrolling document is bridged. SwiftUI still owns the sheet and loading state.
struct AnnouncementReaderBody: NSViewRepresentable {
    let html: String
    var findRequest: AnnouncementFindRequest?
    var onFindResult: (UUID, Bool) -> Void = { _, _ in }
    let onOpenURL: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpenURL: onOpenURL) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .clear
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        context.coordinator.onFindResult = onFindResult
        context.coordinator.findRequest = findRequest
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            context.coordinator.isReady = false
            context.coordinator.performedRequestID = nil
            view.loadHTMLString(html, baseURL: nil)
        } else {
            context.coordinator.performFindIfNeeded(in: view)
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        coordinator.isReady = false
        coordinator.findRequest = nil
        coordinator.onFindResult = { _, _ in }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var onOpenURL: (URL) -> Void
        var findRequest: AnnouncementFindRequest?
        var onFindResult: (UUID, Bool) -> Void = { _, _ in }
        var isReady = false
        var performedRequestID: UUID?
        init(onOpenURL: @escaping (URL) -> Void) { self.onOpenURL = onOpenURL }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            performFindIfNeeded(in: webView)
        }

        func performFindIfNeeded(in webView: WKWebView) {
            guard isReady, let request = findRequest, performedRequestID != request.id else { return }
            performedRequestID = request.id
            let configuration = WKFindConfiguration()
            configuration.backwards = request.backwards
            configuration.caseSensitive = false
            configuration.wraps = true
            // WebKit highlights and scrolls to the match without enabling page JavaScript.
            // An empty query clears the previous highlight when the find bar closes.
            webView.find(request.query, configuration: configuration) { [weak self] result in
                guard let self, self.isReady, self.findRequest?.id == request.id else { return }
                self.onFindResult(request.id, result.matchFound)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url,
                   ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? ""),
                   url.user == nil, url.password == nil { onOpenURL(url) }
                decisionHandler(.cancel)
            } else {
                // loadHTMLString uses about:blank; never navigate the reader to a remote page.
                decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
            }
        }
    }
}
