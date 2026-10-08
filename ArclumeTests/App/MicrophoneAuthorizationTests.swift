import AVFoundation
import Testing
@testable import Arclume

@MainActor
struct MicrophoneAuthorizationTests {
    @Test func decidedStatesNeverRequestPermission() async {
        for status in [AVAuthorizationStatus.authorized, .denied, .restricted] {
            var requests = 0
            let service = MicrophoneAuthorization(status: { status }, request: { requests += 1; return true })
            let granted = await service.requestFromUserAction()
            #expect(granted == (status == .authorized))
            #expect(requests == 0)
        }
    }

    @Test func concurrentUserActionsShareOneRequest() async {
        var requests = 0
        var status = AVAuthorizationStatus.notDetermined
        let service = MicrophoneAuthorization(status: { status }, request: {
            requests += 1
            for _ in 0..<10 { await Task.yield() }
            status = .authorized
            return true
        })
        let first = Task { await service.requestFromUserAction() }
        let second = Task { await service.requestFromUserAction() }
        #expect(await first.value)
        #expect(await second.value)
        #expect(await service.requestFromUserAction())
        #expect(requests == 1)
    }
}
