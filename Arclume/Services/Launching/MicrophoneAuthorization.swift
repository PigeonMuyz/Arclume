//
//  MicrophoneAuthorization.swift
//  Arclume
//

import AVFoundation
import Foundation

/// Only explicit settings actions may request permission. Launching a game,
/// prewarming Wine, and inspecting authorization must never trigger a prompt.
@MainActor
final class MicrophoneAuthorization {
    static let shared = MicrophoneAuthorization(
        status: { AVCaptureDevice.authorizationStatus(for: .audio) },
        request: { await AVCaptureDevice.requestAccess(for: .audio) }
    )

    private let status: () -> AVAuthorizationStatus
    private let request: () async -> Bool
    private var pendingRequest: Task<Bool, Never>?

    init(status: @escaping () -> AVAuthorizationStatus, request: @escaping () async -> Bool) {
        self.status = status
        self.request = request
    }

    func requestFromUserAction() async -> Bool {
        if let pendingRequest { return await pendingRequest.value }
        let current = status()
        guard current == .notDetermined else { return current == .authorized }
        let task = Task { await request() }
        pendingRequest = task
        defer { pendingRequest = nil }
        return await task.value
    }
}
