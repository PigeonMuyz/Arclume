import Testing

@testable import Arclume

@MainActor
struct ShaderOptimizationEstimateTests {
    @Test func remainingTimeUsesMeasuredThroughput() {
        var estimate = ShaderOptimizationEstimate()
        let baseline = estimate.record(.init(processed: 500, total: 1_000, failed: 0, phase: "optimize"), at: 10)
        let measured = estimate.record(.init(processed: 600, total: 1_000, failed: 0, phase: "optimize"), at: 12)
        let completed = estimate.record(.init(processed: 1_000, total: 1_000, failed: 0, phase: "optimize"), at: 20)

        #expect(baseline == nil)
        #expect(measured == .seconds(8))
        #expect(completed == nil)
    }

    @Test func switchingStagesResetsThroughput() {
        var estimate = ShaderOptimizationEstimate()
        _ = estimate.record(.init(processed: 0, total: 100, failed: 0, phase: "dxbc"), at: 10)
        _ = estimate.record(.init(processed: 75, total: 100, failed: 0, phase: "dxbc"), at: 12)
        let metalStart = estimate.record(.init(processed: 5, total: 300, failed: 0, phase: "optimize"), at: 14)
        let metalEstimate = estimate.record(.init(processed: 20, total: 300, failed: 0, phase: "optimize"), at: 17)
        let backup = estimate.record(.init(processed: 0, total: 0, failed: 0, phase: "backup"), at: 18)

        #expect(metalStart == nil)
        #expect(metalEstimate == .seconds(56))
        #expect(backup == nil)
    }
}
