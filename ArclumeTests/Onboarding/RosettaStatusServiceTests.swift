import Testing
import MachO
@testable import Arclume

struct RosettaStatusServiceTests {
    @Test func intelHardwareIsDetectedWhenArm64CapabilitySysctlIsUnavailable() {
        let architecture = RosettaStatusService.resolveMachineArchitecture(
            arm64Capability: nil,
            cpuType: Int32(CPU_TYPE_X86_64),
            processTranslated: false
        )

        #expect(architecture == .intel)
    }

    @Test func translatedX8664ProcessStillIdentifiesAppleSiliconHardware() {
        let architecture = RosettaStatusService.resolveMachineArchitecture(
            arm64Capability: nil,
            cpuType: Int32(CPU_TYPE_X86_64),
            processTranslated: true
        )

        #expect(architecture == .appleSilicon)
    }

    @Test func arm64HardwareTypeIdentifiesAppleSiliconWithoutCapabilitySysctl() {
        let architecture = RosettaStatusService.resolveMachineArchitecture(
            arm64Capability: nil,
            cpuType: Int32(CPU_TYPE_ARM64),
            processTranslated: false
        )

        #expect(architecture == .appleSilicon)
    }

    @Test func unavailableArchitectureEvidenceRemainsUnknown() {
        let architecture = RosettaStatusService.resolveMachineArchitecture(
            arm64Capability: nil,
            cpuType: nil,
            processTranslated: nil
        )

        #expect(architecture == .unknown)
    }

    @Test func intelMacDoesNotRequireRosettaOrProbeItsInstallation() {
        var inspectedInstallation = false
        let service = RosettaStatusService(
            architecture: { .intel },
            installationEvidence: {
                inspectedInstallation = true
                return .unknown
            }
        )

        #expect(service.check() == .notRequired)
        #expect(!inspectedInstallation)
    }

    @Test func appleSiliconReportsInstalledRosetta() {
        let service = RosettaStatusService(
            architecture: { .appleSilicon },
            installationEvidence: { .installed }
        )

        #expect(service.check() == .installed)
    }

    @Test func appleSiliconReportsMissingRosetta() {
        let service = RosettaStatusService(
            architecture: { .appleSilicon },
            installationEvidence: { .missing }
        )

        #expect(service.check() == .missing)
    }

    @Test func unavailableInstallationCheckRemainsUnknown() {
        let service = RosettaStatusService(
            architecture: { .appleSilicon },
            installationEvidence: { .unknown }
        )

        #expect(service.check() == .unknown)
    }

    @Test func unavailableArchitectureRemainsUnknownWithoutCheckingInstallation() {
        var inspectedInstallation = false
        let service = RosettaStatusService(
            architecture: { .unknown },
            installationEvidence: {
                inspectedInstallation = true
                return .missing
            }
        )

        #expect(service.check() == .unknown)
        #expect(!inspectedInstallation)
    }
}
