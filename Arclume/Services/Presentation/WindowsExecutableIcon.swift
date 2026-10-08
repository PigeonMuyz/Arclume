import Foundation

/// Read-only PE resource parser. Never loads a DLL or executes Windows code.
/// https://learn.microsoft.com/windows/win32/debug/pe-format#the-rsrc-section
nonisolated enum WindowsExecutableIcon {
    static let fileLimit = 128 * 1024 * 1024

    static func read(_ url: URL) -> Data? {
        guard url.pathExtension.lowercased() == "exe",
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= fileLimit,
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: fileLimit + 1), data.count <= fileLimit else { return nil }
        return ico(in: data)
    }

    static func ico(in data: Data) -> Data? {
        func number(_ offset: Int, _ width: Int = 4) -> Int? {
            guard offset >= 0, width > 0, offset <= data.count - width else { return nil }
            return (0..<width).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        guard data.count <= fileLimit, number(0, 2) == 0x5a4d,
              let pe = number(0x3c), number(pe) == 0x4550,
              let sectionCount = number(pe + 6, 2), sectionCount > 0, sectionCount <= 96,
              let optionalSize = number(pe + 20, 2), let magic = number(pe + 24, 2),
              magic == 0x10b || magic == 0x20b else { return nil }
        let directories = magic == 0x20b ? 112 : 96
        guard optionalSize >= directories + 24,
              let directoryCount = number(pe + 24 + directories - 4), directoryCount >= 3,
              let resourceRVA = number(pe + 24 + directories + 16), resourceRVA > 0,
              let resourceSize = number(pe + 24 + directories + 20), resourceSize >= 16 else { return nil }
        let sections = pe + 24 + optionalSize
        guard sections <= data.count - sectionCount * 40 else { return nil }
        func fileOffset(_ rva: Int, size: Int) -> Int? {
            for index in 0..<sectionCount {
                let section = sections + index * 40
                guard let address = number(section + 12), let rawSize = number(section + 16), let raw = number(section + 20),
                      rva >= address, rva - address <= rawSize, size <= rawSize - (rva - address),
                      raw + rva - address <= data.count - size else { continue }
                return raw + rva - address
            }
            return nil
        }
        guard let base = fileOffset(resourceRVA, size: resourceSize) else { return nil }
        func entries(_ relative: Int) -> [(id: Int, offset: Int, directory: Bool)]? {
            guard relative >= 0, relative <= resourceSize - 16,
                  let named = number(base + relative + 12, 2), let ids = number(base + relative + 14, 2),
                  named + ids <= 4096, (named + ids) * 8 <= resourceSize - relative - 16 else { return nil }
            return (0..<(named + ids)).compactMap { index in
                let entry = base + relative + 16 + index * 8
                guard let id = number(entry), let offset = number(entry + 4) else { return nil }
                return (id, offset & 0x7fff_ffff, offset & 0x8000_0000 != 0)
            }
        }
        func resources(type: Int) -> [(Int, Data)] {
            guard let category = entries(0)?.first(where: { $0.id == type && $0.directory }),
                  let names = entries(category.offset) else { return [] }
            var result: [(Int, Data)] = [], total = 0
            guard names.count <= 512 else { return [] }
            for name in names {
                guard name.directory, let language = entries(name.offset)?.first(where: { !$0.directory }),
                      language.offset <= resourceSize - 16,
                      let rva = number(base + language.offset), let size = number(base + language.offset + 4),
                      size > 0, size <= 4 * 1024 * 1024, let offset = fileOffset(rva, size: size) else { continue }
                total += size
                guard total <= 8 * 1024 * 1024 else { return [] }
                result.append((name.id, data.subdata(in: offset..<(offset + size))))
            }
            return result
        }
        let images = Dictionary(resources(type: 3), uniquingKeysWith: { first, _ in first })
        for (_, group) in resources(type: 14) {
            guard group.count >= 6, group[0] == 0, group[1] == 0, group[2] == 1, group[3] == 0 else { continue }
            let count = Int(group[4]) | Int(group[5]) << 8
            guard count > 0, count <= 64, count * 14 <= group.count - 6 else { continue }
            var payloads: [(Data, Data)] = []
            for index in 0..<count {
                let start = 6 + index * 14
                let id = Int(group[start + 12]) | Int(group[start + 13]) << 8
                guard let image = images[id] else { continue }
                let expected = (0..<4).reduce(0) { $0 | Int(group[start + 8 + $1]) << ($1 * 8) }
                guard image.count == expected else { continue }
                payloads.append((group.subdata(in: start..<(start + 12)), image))
            }
            guard !payloads.isEmpty, payloads.reduce(0, { $0 + $1.1.count }) <= 8 * 1024 * 1024 else { continue }
            var icon = Data([0, 0, 1, 0, UInt8(payloads.count), 0])
            var offset = 6 + payloads.count * 16
            for (entry, image) in payloads {
                icon.append(entry)
                for shift in 0..<4 { icon.append(UInt8(truncatingIfNeeded: offset >> (shift * 8))) }
                offset += image.count
            }
            for (_, image) in payloads { icon.append(image) }
            return icon
        }
        return nil
    }
}

actor WindowsExecutableIconCache {
    static let shared = WindowsExecutableIconCache()
    private var cache: [String: Data] = [:]
    private var cost = 0
    func load(_ url: URL) -> Data? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = url.path + ":\(values?.fileSize ?? 0):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }
        let data = WindowsExecutableIcon.read(url)
        if cache.count >= 64 || cost + (data?.count ?? 0) > 32 * 1024 * 1024 { cache.removeAll(); cost = 0 }
        cache[key] = data ?? Data()
        cost += data?.count ?? 0
        return data
    }
}
