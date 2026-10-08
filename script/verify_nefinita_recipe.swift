import Foundation
import CryptoKit

// Verify the built App's anonymous download route with the same macOS networking stack.
// Does not execute downloaded scripts, build Wine, or touch user runtime directories.
struct Recipe: Decodable {
    let version: String
    let revision: String
    let files: [String: String]
}
struct WineSource: Decodable {
    let archive: String
    let sha256: String
    let byteCount: Int
    let objectKey: String
}
enum VerificationFailure: Error { case configuration, download, checksum }

do {
    guard (2...3).contains(CommandLine.arguments.count),
          let bundle = Bundle(path: CommandLine.arguments[1]),
          let base = bundle.object(forInfoDictionaryKey: "ArclumeResourceBaseURL") as? String,
          let baseURL = URL(string: base), baseURL.scheme == "https",
          let recipeURL = bundle.url(forResource: "nefinita-build-recipe", withExtension: "json") else {
        throw VerificationFailure.configuration
    }
    let recipe = try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: recipeURL))
    if CommandLine.arguments.count == 3 {
        guard CommandLine.arguments[2] == "--wine-source",
              let sourceURL = bundle.url(forResource: "nefinita-wine-source", withExtension: "json") else {
            throw VerificationFailure.configuration
        }
        let source = try JSONDecoder().decode(WineSource.self, from: Data(contentsOf: sourceURL))
        let (file, response) = try await URLSession.shared.download(from: baseURL.appendingPathComponent(source.objectKey))
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https",
              try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == source.byteCount else {
            throw VerificationFailure.download
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { hash.update(data: data) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == source.sha256 else {
            throw VerificationFailure.checksum
        }
        print("PASS: \(source.archive) verified anonymously through macOS URLSession (\(source.byteCount) bytes)")
    } else {
    for (path, expected) in recipe.files.sorted(by: { $0.key < $1.key }) {
        let key = "components/build-recipe/nefinita/dev.nefinita.build-recipe/\(recipe.version)-\(recipe.revision.prefix(8))/\(expected)/\(path)"
        let (file, response) = try await URLSession.shared.download(from: baseURL.appendingPathComponent(key))
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else {
            throw VerificationFailure.download
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { hash.update(data: data) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
            throw VerificationFailure.checksum
        }
        print("Verified: \(path)")
    }
    print("PASS: \(recipe.files.count) pinned inputs fetched anonymously through macOS URLSession")
    }
} catch {
    print("FAIL: recipe download verification failed; endpoint and credentials omitted")
    exit(1)
}
