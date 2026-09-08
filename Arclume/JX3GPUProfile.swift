import CoreFoundation
import CryptoKit
import Foundation

nonisolated struct JX3GPUProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let fields: [String: String]

    static let performanceKeys: Set<String> = ["gpuscore", "gputype", "gpuname", "videotype", "bdtype"]

    static func owns(_ section: String, _ key: String) -> Bool {
        if section == "performance" { return performanceKeys.contains(key) }
        if section == "device" {
            return key == "count" || key.range(of: "^description_[0-9]+$", options: .regularExpression) != nil
        }
        return false
    }

    static func read(from data: Data) throws -> Self {
        let document = try JX3GPUConfigDocument(data: data)
        let fields = document.values.filter { entry in
            let parts = entry.key.split(separator: ".", maxSplits: 1).map(String.init)
            return parts.count == 2 && owns(parts[0], parts[1])
        }
        let digest = SHA256.hash(data: try JSONEncoder.sorted.encode(fields))
            .map { String(format: "%02x", $0) }.joined()
        let result = Self(id: "import-\(digest)", name: fields["performance.gpuname"] ?? "", fields: fields)
        try result.validate()
        return result
    }

    func validate() throws {
        guard !name.isEmpty, name.count <= 200, fields.count <= 71,
              let gpuName = fields["performance.gpuname"], !gpuName.isEmpty else {
            throw JX3GPUProfileError.invalidProfile
        }
        for (field, value) in fields {
            let parts = field.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, Self.owns(parts[0], parts[1]),
                  !value.isEmpty, value.count <= 256,
                  value.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw JX3GPUProfileError.invalidProfile
            }
            if parts[1] != "gpuname" && !parts[1].hasPrefix("description_") {
                guard let number = Int(value), (0...10_000_000).contains(number) else {
                    throw JX3GPUProfileError.invalidProfile
                }
            }
            if parts[0] == "device" {
                let number = parts[1] == "count" ? Int(value) : Int(parts[1].dropFirst(12))
                guard let number, (0...64).contains(number) else { throw JX3GPUProfileError.invalidProfile }
            }
        }
    }
}

nonisolated enum JX3GPUProfileError: LocalizedError {
    case invalidProfile, missingConfig, corruptState, concurrentChange, tooManyProfiles

    var errorDescription: String? {
        switch self {
        case .invalidProfile: "显卡配置无效，请选择包含 GPUName 的 machine_config.ini。"
        case .missingConfig: "未找到 machine_config.ini，请先完成游戏初始化。"
        case .corruptState: "显卡伪装恢复记录无法读取，未覆盖配置；请保留记录后排查。"
        case .concurrentChange: "游戏配置在操作期间发生变化，请关闭游戏后重试。"
        case .tooManyProfiles: "当前容器最多保存 20 个自定义显卡预设。"
        }
    }
}

/// Keeps the source encoding, comments and unrelated values when changing only GPU fields.
nonisolated struct JX3GPUConfigDocument {
    private let text: String
    private let encoding: String.Encoding
    private let newline: String

    static func readData(at url: URL, maximumBytes: Int = 65_536) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw JX3GPUProfileError.invalidProfile }
        return data
    }

    init(data: Data) throws {
        guard data.count <= 65_536 else { throw JX3GPUProfileError.invalidProfile }
        if String(data: data, encoding: .utf8) != nil {
            text = String(decoding: data, as: UTF8.self)
            encoding = .utf8
        } else {
            let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            ))
            guard let decoded = String(data: data, encoding: gb) else { throw JX3GPUProfileError.invalidProfile }
            text = decoded
            encoding = gb
        }
        newline = text.contains("\r\n") ? "\r\n" : "\n"
    }

    private func normalized(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
    }

    private func entry(_ line: String) -> (String, String)? {
        let clean = normalized(line)
        guard !clean.hasPrefix(";"), !clean.hasPrefix("#"), let separator = clean.firstIndex(of: "=") else { return nil }
        return (clean[..<separator].trimmingCharacters(in: .whitespaces).lowercased(),
                clean[clean.index(after: separator)...].trimmingCharacters(in: .whitespaces))
    }

    var values: [String: String] {
        var values: [String: String] = [:]
        var section = ""
        for line in text.components(separatedBy: .newlines) {
            let clean = normalized(line)
            if clean.hasPrefix("["), clean.hasSuffix("]") {
                section = clean.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
            } else if let (key, value) = entry(line) {
                values["\(section).\(key)"] = value
            }
        }
        return values
    }

    func hasSection(_ section: String) -> Bool {
        text.components(separatedBy: .newlines).contains { normalized($0).lowercased() == "[\(section)]" }
    }

    func replacingGPUFields(with fields: [String: String], removeEmptyDevice: Bool = false) throws -> Data {
        var pending = fields
        var section = ""
        var output: [String] = []
        var seen = Set<String>()
        func appendPending() {
            for field in pending.keys.sorted() where field.hasPrefix(section + ".") {
                output.append("\(field.dropFirst(section.count + 1))=\(pending.removeValue(forKey: field)!)")
                seen.insert(field)
            }
        }
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let clean = normalized(line)
            if clean.hasPrefix("["), clean.hasSuffix("]") {
                appendPending()
                section = clean.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
                output.append(line)
            } else if let (key, oldValue) = entry(line), JX3GPUProfile.owns(section, key) {
                let field = "\(section).\(key)"
                if seen.insert(field).inserted, let value = fields[field] {
                    output.append(value == oldValue ? line : "\(key)=\(value)")
                }
                pending.removeValue(forKey: field)
            } else {
                output.append(line)
            }
        }
        appendPending()
        for target in ["performance", "device"] where pending.keys.contains(where: { $0.hasPrefix(target + ".") }) {
            output.append("[\(target == "device" ? "Device" : "Performance")]")
            section = target
            appendPending()
        }
        if removeEmptyDevice {
            for index in output.indices.reversed() where normalized(output[index]).lowercased() == "[device]" {
                let end = ((index + 1)..<output.count).first { normalized(output[$0]).hasPrefix("[") } ?? output.count
                if output[(index + 1)..<end].allSatisfy({ normalized($0).isEmpty }) {
                    output.removeSubrange(index..<end)
                }
            }
        }
        guard let data = output.joined(separator: newline).data(using: encoding) else {
            throw JX3GPUProfileError.invalidProfile
        }
        return data
    }
}

nonisolated private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
