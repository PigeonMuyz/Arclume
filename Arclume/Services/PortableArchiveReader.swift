import Foundation
import Darwin

/// Read entries ourselves: never let an archive restore links, permissions or absolute paths.
/// System libarchive ABI: https://github.com/libarchive/libarchive/blob/master/libarchive/archive.h
nonisolated enum PortableArchiveReader {
    static let extensions = ["zip", "7z", "rar"]
    static func supports(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "Arclume.Portable", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func safePath(_ path: String) -> Bool {
        guard GameAdaptationRules.safeRelativePath(path), path.utf8.count <= 1024 else { return false }
        return path.split(separator: "/").allSatisfy { part in
            let name = String(part).lowercased()
            let stem = name.split(separator: ".").first.map(String.init) ?? name
            return !name.hasSuffix(".") && !name.hasSuffix(" ")
                && !name.contains(where: { "<>\"|?*".contains($0) })
                && name != PortableSoftwareService.receiptName
                && !["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"].contains(stem)
        }
    }

    static func extract(_ source: URL, to destination: URL, byteLimit: Int64 = 8 * 1024 * 1024 * 1024,
                        entryLimit: Int = 50_000) throws {
        guard supports(source), (try source.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
            throw failure("请选择 ZIP、7z 或 RAR 压缩包。")
        }
        guard destination.standardizedFileURL == destination.resolvingSymlinksInPath(),
              !FileManager.default.fileExists(atPath: destination.path) else { throw GameRemovalError.unsafePath }
        // macOS ships this library in its dyld cache; no downloaded command or shell is involved.
        guard let library = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL) else {
            throw failure("系统解压组件不可用。")
        }
        defer { dlclose(library) }
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let address = dlsym(library, name) else { throw failure("系统解压组件不支持此格式。") }
            return unsafeBitCast(address, to: T.self)
        }
        typealias Status = @convention(c) (OpaquePointer) -> Int32
        typealias Text = @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
        let create = try symbol("archive_read_new", (@convention(c) () -> OpaquePointer?).self)
        let free = try symbol("archive_read_free", Status.self)
        let open = try symbol("archive_read_open_filename", (@convention(c) (OpaquePointer, UnsafePointer<CChar>, Int) -> Int32).self)
        let next = try symbol("archive_read_next_header", (@convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32).self)
        let read = try symbol("archive_read_data", (@convention(c) (OpaquePointer, UnsafeMutableRawPointer, Int) -> Int).self)
        let pathname = try symbol("archive_entry_pathname_utf8", Text.self)
        let hardlink = try symbol("archive_entry_hardlink", Text.self)
        let symlink = try symbol("archive_entry_symlink", Text.self)
        let filetype = try symbol("archive_entry_filetype", (@convention(c) (OpaquePointer) -> mode_t).self)
        let size = try symbol("archive_entry_size", (@convention(c) (OpaquePointer) -> Int64).self)
        let encrypted = try symbol("archive_entry_is_encrypted", Status.self)
        guard let reader = create() else { throw failure("无法创建解压任务。") }
        defer { _ = free(reader) }
        for name in ["archive_read_support_format_zip", "archive_read_support_format_7zip", "archive_read_support_format_rar", "archive_read_support_format_rar5"] {
            guard try symbol(name, Status.self)(reader) == 0 else { throw failure("系统不支持所需的解压格式。") }
        }
        guard source.path.withCString({ open(reader, $0, 64 * 1024) }) == 0 else {
            throw failure("无法读取压缩包：格式不支持、已加密或文件损坏。")
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
        var seen = Set<String>(), spellings: [String: String] = [:]
        var count = 0, total: Int64 = 0
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 64 * 1024, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            try Task.checkCancellation()
            var entry: OpaquePointer?
            let status = next(reader, &entry)
            if status == 1 { break } // ARCHIVE_EOF; warnings are not accepted as success.
            guard status == 0, let entry, encrypted(entry) == 0, let raw = pathname(entry),
                  let decoded = String(validatingCString: raw) else {
                throw failure("解压失败：压缩包损坏、已加密或名称编码不受支持。")
            }
            let path = decoded.hasSuffix("/") ? String(decoded.dropLast()) : decoded
            count += 1
            let type = filetype(entry)
            guard count <= entryLimit, safePath(path), hardlink(entry) == nil, symlink(entry) == nil,
                  type == mode_t(S_IFREG) || type == mode_t(S_IFDIR),
                  seen.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw failure("压缩包包含不安全、重复的路径或过多文件，未导入。")
            }
            // Reject case/Unicode collisions in parent directories too (Wine is case-insensitive).
            var prefix = ""
            for part in path.split(separator: "/") {
                prefix += (prefix.isEmpty ? "" : "/") + part
                let folded = prefix.precomposedStringWithCanonicalMapping.lowercased()
                if let previous = spellings[folded], previous != prefix { throw GameRemovalError.unsafePath }
                spellings[folded] = prefix
            }
            let url = destination.appendingPathComponent(path)
            if type == mode_t(S_IFDIR) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                continue
            }
            guard size(entry) >= 0, size(entry) <= byteLimit - total else { throw failure("解压内容超过 8 GB 安全限制。") }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw GameRemovalError.unsafePath }
            let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? output.close() }
            var written: Int64 = 0
            while true {
                try Task.checkCancellation()
                let bytes = read(reader, buffer, 64 * 1024)
                guard bytes >= 0 else { throw failure("压缩数据损坏或加密，未导入。") }
                if bytes == 0 { break }
                guard Int64(bytes) <= byteLimit - total else { throw failure("解压内容超过 8 GB 安全限制。") }
                total += Int64(bytes); written += Int64(bytes)
                try output.write(contentsOf: Data(bytes: buffer, count: bytes))
            }
            guard written == size(entry) else { throw failure("压缩包文件长度校验失败。") }
        }
        guard count > 0 else { throw failure("压缩包为空。") }
        complete = true
    }
}
