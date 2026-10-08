import Foundation

/// Translates a small allowlist of upstream build events, never raw log output.
nonisolated enum NefinitaBuildProgress {
    static func message(for line: String) -> String? {
        guard line.range(of: "^\\[[0-9]{2}:[0-9]{2}:[0-9]{2}\\] ", options: .regularExpression) != nil else { return nil }
        let event = String(line.dropFirst(11))
        if event.hasPrefix("creating archive:") { return "打包 Nefinita 运行时…" }
        if event.contains("signing native Wine binaries") { return "签署 Nefinita 运行时…" }
        if event == "applying FineWine patches" { return "应用 FineWine 补丁…" }
        if event == "verifying patch checksums" { return "准备 FineWine 补丁…" }
        let actions = [("downloading ", "下载"), ("extracting ", "解压"),
                       ("configuring ", "配置编译环境："), ("building ", "编译"),
                       ("installing ", "安装"), ("cached ", "使用已下载的")]
        guard let action = actions.first(where: { event.hasPrefix($0.0) }) else { return nil }
        let detail = String(event.dropFirst(action.0.count))
        // For download URLs classify the archive only, never the hostname or query.
        let subject = (action.0 == "downloading " ? URL(string: detail)?.lastPathComponent : detail)?.lowercased() ?? ""
        let components = [("finewine", "FineWine 补丁"), ("freetype", "FreeType"),
                          ("gstreamer", "GStreamer"), ("gst-", "GStreamer 插件"),
                          ("glib", "GLib"), ("libffi", "libffi"), ("libpng", "libpng"),
                          ("zlib", "zlib"), ("jpeg", "JPEG"), ("libxml", "libxml"),
                          ("gnutls", "GnuTLS"), ("nettle", "Nettle"), ("gmp", "GMP"),
                          ("libtasn1", "libtasn1"), ("pcre2", "PCRE2"), ("orc", "ORC"),
                          ("libogg", "Ogg"), ("libvorbis", "Vorbis"), ("ffmpeg", "FFmpeg"),
                          ("mpg123", "mpg123"), ("nasm", "NASM"), ("wine", "Wine"),
                          ("crossover", "Wine 源码")]
        let name = components.first(where: { subject.contains($0.0) })?.1 ?? "依赖组件"
        return "\(action.1) \(name)…"
    }

    static func monitor(log: URL, onMessage: @escaping @Sendable (String) -> Void) -> Task<Void, Never> {
        // Open and seek before launching the script, so early events are not missed.
        let reader = try? FileHandle(forReadingFrom: log)
        _ = try? reader?.seekToEnd()
        return Task.detached(priority: .utility) {
            guard let reader else { return }
            defer { try? reader.close() }
            var pending = Data()
            var lastMessage: String?
            while !Task.isCancelled {
                let chunk: Data
                do { chunk = try reader.read(upToCount: 64 * 1024) ?? Data() }
                catch { return }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    if let message = message(for: line), message != lastMessage {
                        lastMessage = message
                        onMessage(message)
                    }
                }
                // curl progress and compiler lines can be very long; retain no unbounded tail.
                if pending.count > 64 * 1024 { pending.removeAll(keepingCapacity: false) }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
}
