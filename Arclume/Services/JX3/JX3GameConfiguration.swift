import CoreFoundation
import Foundation

nonisolated enum JX3GameConfiguration {
    static func configURL(in bottleURL: URL, installation: OnlineGameInstallation? = nil) -> URL {
        let directory = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL, installation: installation)
            ?? OnlineGameDiscovery.defaultJX3GameDirectory(in: bottleURL)
        return directory.appendingPathComponent("config.ini")
    }
}

nonisolated struct JX3INIText {
    let contents: String
    private let encoding: String.Encoding
    private let bom: [UInt8]

    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    init?(data: Data) {
        let variants: [(bom: [UInt8], encoding: String.Encoding)] = [
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFF, 0xFE], .utf16LittleEndian),
            ([0xFE, 0xFF], .utf16BigEndian)
        ]
        let variant = variants.first { data.starts(with: $0.bom) }
        let bom = variant?.bom ?? []
        let payload = Data(data.dropFirst(bom.count))
        let encodings = variant.map { [$0.encoding] } ?? [.utf8, Self.gb18030]
        for encoding in encodings {
            guard let contents = String(data: payload, encoding: encoding),
                  !contents.utf8.contains(0),
                  contents.data(using: encoding) == payload
            else { continue }
            self.contents = contents
            self.encoding = encoding
            self.bom = bom
            return
        }
        return nil
    }

    func encode(_ updatedContents: String) throws -> Data {
        guard let payload = updatedContents.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return Data(bom) + payload
    }
}
