import Darwin
import Foundation
import MachO

enum RosettaMachineArchitecture: Equatable, Sendable {
    case appleSilicon
    case intel
    case unknown
}

enum RosettaInstallationEvidence: Equatable, Sendable {
    case installed
    case missing
    case unknown
}

enum RosettaStatus: Equatable, Sendable {
    case notRequired
    case installed
    case missing
    case unknown
}

struct RosettaStatusService {
    private let architecture: () -> RosettaMachineArchitecture
    private let installationEvidence: () -> RosettaInstallationEvidence

    init(
        architecture: @escaping () -> RosettaMachineArchitecture,
        installationEvidence: @escaping () -> RosettaInstallationEvidence
    ) {
        self.architecture = architecture
        self.installationEvidence = installationEvidence
    }

    init() {
        self.init(
            architecture: Self.detectMachineArchitecture,
            installationEvidence: Self.detectInstallationEvidence
        )
    }

    func check() -> RosettaStatus {
        switch architecture() {
        case .intel:
            .notRequired
        case .appleSilicon:
            switch installationEvidence() {
            case .installed: .installed
            case .missing: .missing
            case .unknown: .unknown
            }
        case .unknown:
            .unknown
        }
    }

    private static func detectMachineArchitecture() -> RosettaMachineArchitecture {
        resolveMachineArchitecture(
            arm64Capability: booleanSysctlValue("hw.optional.arm64"),
            cpuType: integerSysctlValue("hw.cputype"),
            processTranslated: processIsTranslated()
        )
    }

    static func resolveMachineArchitecture(
        arm64Capability: Bool?,
        cpuType: Int32?,
        processTranslated: Bool?
    ) -> RosettaMachineArchitecture {
        // The translation flag identifies the host when this app itself runs as
        // x86_64. Hardware sysctls remain the source of truth for native runs.
        if processTranslated == true { return .appleSilicon }
        if arm64Capability == true || cpuType == Int32(CPU_TYPE_ARM64) {
            return .appleSilicon
        }
        if cpuType == Int32(CPU_TYPE_X86_64) || arm64Capability == false {
            return .intel
        }
        return .unknown
    }

    private static func integerSysctlValue(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size else {
            return nil
        }
        return value
    }

    private static func booleanSysctlValue(_ name: String) -> Bool? {
        guard let value = integerSysctlValue(name) else { return nil }
        return switch value {
        case 0: false
        case 1: true
        default: nil
        }
    }

    private static func processIsTranslated() -> Bool? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0) == 0 else {
            // Apple documents ENOENT as the native, non-translated case.
            return errno == ENOENT ? false : nil
        }
        guard size == MemoryLayout<Int32>.size else { return nil }
        return switch value {
        case 0: false
        case 1: true
        default: nil
        }
    }

    private static func detectInstallationEvidence() -> RosettaInstallationEvidence {
        // Inspect Rosetta's system files without trying to launch an Intel binary;
        // launching one can itself prompt macOS to install Rosetta.
        let markers = [
            "/Library/Apple/usr/libexec/oah/libRosettaRuntime",
            "/Library/Apple/usr/share/rosetta/rosetta"
        ]
        var probeWasUnavailable = false

        for marker in markers {
            var metadata = stat()
            let result = marker.withCString { fstatat(AT_FDCWD, $0, &metadata, 0) }
            if result == 0 { return .installed }

            switch errno {
            case ENOENT, ENOTDIR:
                continue
            default:
                probeWasUnavailable = true
            }
        }

        return probeWasUnavailable ? .unknown : .missing
    }
}
