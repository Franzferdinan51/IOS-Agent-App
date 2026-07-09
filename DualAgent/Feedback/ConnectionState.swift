//
//  ConnectionState.swift
//  DualAgent
//
//  Lightweight published connection-state machine that drives the
//  ConnectionStatePill on the Sessions tab. Wraps `AuthManager` and
//  (for OpenClaw) the live `OpenClawRPC` socket lifecycle. Backend-neutral.
//

import Foundation
import Combine

@MainActor
final class ConnectionState: ObservableObject {
    enum Status: Equatable {
        case unknown
        case offline(reason: String)
        case connecting
        case ready
    }

    @Published private(set) var status: Status = .unknown

    private weak var auth: AuthManager?
    private var bag: Set<AnyCancellable> = []

    func bind(_ authManager: AuthManager) {
        self.auth = authManager
        bag.removeAll()
        authManager.$isAuthenticated
            .removeDuplicates()
            .sink { [weak self] authed in
                guard let self else { return }
                if authed {
                    self.status = .connecting
                    // Brief delay so the user sees the "Connecting…" pill
                    // before it transitions to ready. Real RPC handshake
                    // happens during login(); the 0.4s grace period is for
                    // telemetry/debug hookup.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if self.status != .offline(reason: "") {
                            self.status = .ready
                        }
                    }
                } else {
                    self.status = .offline(reason: "Not signed in")
                }
            }
            .store(in: &bag)
    }

    func markOffline(reason: String) {
        status = .offline(reason: reason)
    }

    func markConnecting() {
        status = .connecting
    }

    func markReady() {
        status = .ready
    }
}
