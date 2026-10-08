import CryptoKit
import Foundation

/// Fixed, reviewed YY 9.58 compatibility helper. Never a downloaded patch engine.
nonisolated enum YYLaunchSupport {
    static let helperSHA256 = "fb8d4c01a3d6a5034e84fc3bba74718121a1c59aee795a6b521cf919f5114316"
    static let requiredFiles: [(String, String)] = [
        ("YY.exe", "bcf7304c2e42bdbc00cb7fb5da95dabb07e149e5f13852b6578e0d42aa041308"),
        ("9.58.0.0/YY.exe", "62762a7db9c619db77d6b2b816ae1debabb4446813a9d309e68eba58142f1ce6"),
        ("9.58.0.0/components/com.yy.processservice/197124/gslb.dll", "5813bd9c8c0b6d7360f9b369e744ab0fac2a0294aa2b10fc43b1927fbe40e108"),
        ("9.58.0.0/components/com.yy.cefdev2/131387/yycefdev2.dll", "9b80204d577eaaadfda10c12d367c2255c9860fb9b7bbce8f9ddf41d9a9be676")
    ]

    static func failure(_ detail: String) -> NSError {
        NSError(domain: "Arclume.YYSupport", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "YY 兼容启动未执行：\(detail) 未修改游戏、登录数据或 DLL。"])
    }

    static func verify(_ file: URL, sha256: String) throws {
        let normalized = file.standardizedFileURL
        guard normalized.resolvingSymlinksInPath() == normalized,
              let attributes = try? normalized.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size <= 32 * 1024 * 1024 else {
            throw failure("缺少或无法安全读取 \(file.lastPathComponent)。")
        }
        let data = try Data(contentsOf: normalized)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw failure("\(file.lastPathComponent) 与已验证版本不匹配，请更新对应适配；不会尝试未知地址补丁。") }
    }

    static func arguments(executable: URL?, bottle: URL, userArguments: [String],
                          helper: URL? = Bundle.main.url(forResource: "yy-launch-support", withExtension: "exe")) throws -> [String]? {
        guard let executable, let rule = GameAdaptationRules.all.first(where: {
            $0.launchSupport == "yy-9.58-v1" && executable.standardizedFileURL == $0.directory(in: bottle).appendingPathComponent($0.executable)
        }) else { return nil }
        guard rule.allows(executable, in: bottle) else { throw failure("入口不在规定的 YY 安装目录。") }
        guard rule.recognizes(executable) else { throw failure("YY 安装不完整，请检查主程序及 yylauncher.exe。") }
        guard userArguments.isEmpty else { throw failure("请先清空 YY 的自定义启动参数；此适配使用经过验证的固定参数。") }
        guard let helper else { throw failure("App 缺少兼容启动组件，请重新安装 Arclume。") }
        try verify(helper, sha256: helperSHA256)
        for (path, hash) in requiredFiles {
            try verify(rule.directory(in: bottle).appendingPathComponent(path), sha256: hash)
        }
        // Wine accepts the host path. The GUI-subsystem helper creates the fixed YY
        // process and applies checked memory changes before its DLLs execute.
        return [helper.path, "--run-in-process-gpu"]
    }
}
