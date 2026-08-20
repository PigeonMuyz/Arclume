//
//  NativeAppRuntime.swift
//  Procyon
//

import Foundation

struct NativeAppRuntimeSession: Identifiable, Equatable {
    let gameID: String
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let startedAt: Date

    var id: String { gameID }
}

enum NativeAppRuntimePhase: Equatable {
    case launching
    case running(processIdentifier: pid_t)
    case stopping(processIdentifier: pid_t)
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .launching, .running, .stopping:
            return true
        case .failed:
            return false
        }
    }
}

enum NativeAppRuntimeError: LocalizedError {
    case applicationExitedDuringLaunch

    var errorDescription: String? {
        switch self {
        case .applicationExitedDuringLaunch:
            return L10n.string("The native app exited while it was launching.")
        }
    }
}
