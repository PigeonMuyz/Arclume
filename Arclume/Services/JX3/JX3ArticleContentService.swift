import Foundation

nonisolated struct JX3ArticleContent: Sendable {
    let markdown: String
    let readerHTML: String
}

nonisolated enum JX3ArticleContentError: Error, Equatable, LocalizedError {
    case unsupportedSource
    case invalidResponse
    case serviceRejected
    case articleUnavailable
    case emptyContent
    case responseTooLarge
    case httpStatus(Int)
    case timedOut
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "不支持该剑网3公告或新闻地址。"
        case .invalidResponse:
            return "剑网3公告服务返回了无法识别的数据。"
        case .serviceRejected:
            return "剑网3公告服务暂不可用，请稍后重试。"
        case .articleUnavailable:
            return "找不到这篇剑网3公告或新闻。"
        case .emptyContent:
            return "这篇剑网3公告或新闻暂无正文。"
        case .responseTooLarge:
            return "剑网3公告正文超过 4 MiB 限制。"
        case .httpStatus(let statusCode):
            return "获取剑网3公告失败（HTTP \(statusCode)）。"
        case .timedOut:
            return "获取剑网3公告超时，请稍后重试。"
        case .requestFailed:
            return "获取剑网3公告失败，请检查网络连接。"
        }
    }
}

nonisolated enum JX3ArticleContentService {
    private static let maximumResponseBytes = 4 * 1_024 * 1_024
    private static let requestTimeout: TimeInterval = 30

    private enum ArticleKind {
        case announcement(kid: String)
        case news(catid: String, id: String)
    }

    @concurrent static func load(from sourceURL: URL) async throws -> JX3ArticleContent {
        try Task.checkCancellation()
        let requestURL = try endpoint(for: sourceURL)

        var request = URLRequest(
            url: requestURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.setValue("application/json, text/javascript", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout

        let redirectDelegate = JX3ArticleRedirectDelegate()
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()

            guard let responseURL = response.url,
                  isAllowedWebURL(responseURL) else {
                throw JX3ArticleContentError.unsupportedSource
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JX3ArticleContentError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw JX3ArticleContentError.httpStatus(httpResponse.statusCode)
            }
            guard httpResponse.expectedContentLength <= Int64(maximumResponseBytes) else {
                throw JX3ArticleContentError.responseTooLarge
            }

            var data = Data()
            if httpResponse.expectedContentLength > 0 {
                data.reserveCapacity(min(Int(httpResponse.expectedContentLength), maximumResponseBytes))
            }
            var byteCount = 0
            for try await byte in bytes {
                if byteCount.isMultiple(of: 4_096) {
                    try Task.checkCancellation()
                }
                guard byteCount < maximumResponseBytes else {
                    throw JX3ArticleContentError.responseTooLarge
                }
                data.append(byte)
                byteCount += 1
            }
            try Task.checkCancellation()

            let conversionTask = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let content = try Self.decode(data, sourceURL: sourceURL)
                try Task.checkCancellation()
                return content
            }
            return try await withTaskCancellationHandler {
                try await conversionTask.value
            } onCancel: {
                conversionTask.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as JX3ArticleContentError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled {
                throw CancellationError()
            }
            if error.code == .timedOut {
                throw JX3ArticleContentError.timedOut
            }
            throw JX3ArticleContentError.requestFailed
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw JX3ArticleContentError.requestFailed
        }
    }

    static func endpoint(for sourceURL: URL) throws -> URL {
        let kind = try articleKind(for: sourceURL)
        var components = URLComponents(string: "https://jx3.xoyo.com/api.php")!
        switch kind {
        case .announcement(let kid):
            components.queryItems = [
                URLQueryItem(name: "op", value: "search_api"),
                URLQueryItem(name: "action", value: "get_customer_article_detail"),
                URLQueryItem(name: "game", value: "jx3"),
                URLQueryItem(name: "kid", value: kid),
            ]
        case .news(let catid, let id):
            components.queryItems = [
                URLQueryItem(name: "op", value: "search_api"),
                URLQueryItem(name: "action", value: "get_article_detail"),
                URLQueryItem(name: "catid", value: catid),
                URLQueryItem(name: "id", value: id),
            ]
        }
        guard let url = components.url else {
            throw JX3ArticleContentError.unsupportedSource
        }
        return url
    }

    static func decode(_ data: Data, sourceURL: URL) throws -> JX3ArticleContent {
        let kind = try articleKind(for: sourceURL)
        guard data.count <= maximumResponseBytes else {
            throw JX3ArticleContentError.responseTooLarge
        }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JX3ArticleContentError.invalidResponse
        }
        guard let object = root as? [String: Any] else {
            throw JX3ArticleContentError.invalidResponse
        }
        guard Self.isSuccessCode(object["code"]) else {
            throw JX3ArticleContentError.serviceRejected
        }
        guard let payload = object["data"] else {
            throw JX3ArticleContentError.invalidResponse
        }

        let article: [String: Any]
        switch kind {
        case .announcement:
            guard let item = payload as? [String: Any] else {
                throw JX3ArticleContentError.invalidResponse
            }
            article = item
        case .news(_, let id):
            guard let items = payload as? [[String: Any]] else {
                throw JX3ArticleContentError.invalidResponse
            }
            guard let item = items.first(where: { Self.identifier($0["id"]) == id }) else {
                throw JX3ArticleContentError.articleUnavailable
            }
            article = item
        }

        // Current official responses use `content`; some deployments expose the same
        // HTML under `contentHTML`, so accept that as a compatibility fallback.
        let html = Self.nonEmptyString(article["content"])
            ?? Self.nonEmptyString(article["contentHTML"])
        guard let html else {
            throw JX3ArticleContentError.emptyContent
        }

        let markdown: String
        do {
            markdown = try JX3HTMLToMarkdown.convert(html, articleURL: sourceURL)
        } catch {
            throw JX3ArticleContentError.invalidResponse
        }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JX3ArticleContentError.emptyContent
        }
        try Task.checkCancellation()
        let styledMarkdown = try JX3HTMLToMarkdown.convert(html, articleURL: sourceURL, preserveTextColors: true)
        return JX3ArticleContent(markdown: markdown, readerHTML: try ArticleReaderDocument.make(markdown: styledMarkdown))
    }

    private static func articleKind(for sourceURL: URL) throws -> ArticleKind {
        guard isAllowedWebURL(sourceURL),
              let components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              components.fragment == nil else {
            throw JX3ArticleContentError.unsupportedSource
        }

        if components.path == "/announce/gg.html" {
            let idItems = (components.queryItems ?? []).filter { $0.name == "id" }
            guard idItems.count == 1,
                  let id = idItems[0].value,
                  isPositiveASCIIDecimal(id) else {
                throw JX3ArticleContentError.unsupportedSource
            }
            return .announcement(kid: id)
        }

        guard let captureRegex = try? NSRegularExpression(pattern: "^/show-([0-9]+)-([0-9]+)-[0-9]+\\.html$"),
              let captureMatch = captureRegex.firstMatch(
                in: components.path,
                range: NSRange(components.path.startIndex..., in: components.path)
              ),
              let catidRange = Range(captureMatch.range(at: 1), in: components.path),
              let idRange = Range(captureMatch.range(at: 2), in: components.path) else {
            throw JX3ArticleContentError.unsupportedSource
        }
        let catid = String(components.path[catidRange])
        let id = String(components.path[idRange])
        guard isPositiveASCIIDecimal(catid), isPositiveASCIIDecimal(id) else {
            throw JX3ArticleContentError.unsupportedSource
        }
        return .news(catid: catid, id: id)
    }

    private static func isSuccessCode(_ value: Any?) -> Bool {
        if let value = value as? Int {
            return value == 1
        }
        if let value = value as? String {
            return value == "1"
        }
        return false
    }

    private static func identifier(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? Int {
            return String(value)
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func isPositiveASCIIDecimal(_ value: String) -> Bool {
        guard value.range(of: "^[0-9]+$", options: .regularExpression) != nil,
              let integer = Int(value) else {
            return false
        }
        return integer > 0
    }

    fileprivate static func isAllowedWebURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.lowercased() == "jx3.xoyo.com",
              components.user == nil,
              components.password == nil else {
            return false
        }
        return components.port == nil
            || (scheme == "https" && components.port == 443)
            || (scheme == "http" && components.port == 80)
    }
}

nonisolated private final class JX3ArticleRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              JX3ArticleContentService.isAllowedWebURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
