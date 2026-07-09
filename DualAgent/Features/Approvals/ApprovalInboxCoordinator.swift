//
//  ApprovalInboxCoordinator.swift
//  DualAgent
//
//  Subscribes to the active backend for pending approval events and
//  exposes them via `@Published pendingApprovals`. Backend-neutral:
//  - OpenClaw: subscribes to `OpenClawRPC.events()` for
//    `exec.approval.requested` / `plugin.approval.requested`.
//  - Hermes: stub for now (Hermes events arrive on the SSE channel; the
//    chat coordinator handles transient approvals there).
//
//  Presented by `ApprovalInboxView` from a sheet attached to MainTabView.
//

import Foundation
import Combine

@MainActor
final class ApprovalInboxCoordinator: ObservableObject {
    @Published private(set) var pending: [ApprovalRequest] = []
    @Published var presentedSheet: Bool = false

    private weak var auth: AuthManager?
    private var cancellables: Set<AnyCancellable> = []
    private var streamSubscriptionTask: Task<Void, Never>?

    func bind(_ authManager: AuthManager) {
        self.auth = authManager
        subscribeToOpenClaw()
    }

    func unbind() {
        streamSubscriptionTask?.cancel()
        streamSubscriptionTask = nil
        cancellables.removeAll()
    }

    func enqueue(_ request: ApprovalRequest) {
        pending.append(request)
        presentedSheet = true
    }

    func resolve(_ request: ApprovalRequest, decision: ApprovalRequest.Decision) {
        pending.removeAll { $0.id == request.id }

        // Best-effort transport-specific resolution.
        if let auth, auth.currentBackendType == .openclaw,
           let rpc = (auth.backend as? OpenClawBackend)?.rpcSocket {
            Task {
                do {
                    let method = request.kind == .exec ? "exec.approval.resolve" : "plugin.approval.resolve"
                    _ = try await rpc.requestRaw(method, params: [
                        "id": request.id,
                        "decision": decision.rawValue,
                    ])
                } catch {
                    // Surface failure later; for now, remove from inbox.
                    Haptic.error()
                }
            }
        }
        Haptic.tap()
    }

    // MARK: - OpenClaw event subscription

    private func subscribeToOpenClaw() {
        guard let auth else { return }
        let backend = auth.backend
        guard let openClaw = backend as? OpenClawBackend else { return }
        guard let rpc = openClaw.rpcSocket else { return }
        streamSubscriptionTask?.cancel()
        streamSubscriptionTask = Task { [weak self] in
            for await event in rpc.events() {
                guard let self else { break }
                self.handleOpenClawEvent(event)
            }
        }
    }

    private func handleOpenClawEvent(_ event: OpenClawRPC.ServerEvent) {
        switch event.event {
        case "exec.approval.requested":
            guard let id = (event.payload["id"] as? String) ?? (event.payload["approvalId"] as? String) else { return }
            let title = (event.payload["command"] as? String) ?? "Run a command"
            let detail = (event.payload["description"] as? String) ?? (event.payload["command"] as? String) ?? ""
            let allowed = parseAllowed(from: event.payload["allowedDecisions"])
            enqueue(
                ApprovalRequest(
                    id: id,
                    kind: .exec,
                    title: title,
                    detail: detail,
                    command: (event.payload["command"] as? String),
                    agentId: (event.payload["agentId"] as? String),
                    sessionKey: (event.payload["sessionKey"] as? String),
                    expiresAt: nil,
                    allowedDecisions: allowed
                )
            )
        case "plugin.approval.requested":
            guard let id = (event.payload["id"] as? String) ?? (event.payload["approvalId"] as? String) else { return }
            let title = (event.payload["title"] as? String) ?? "Plugin approval"
            let detail = (event.payload["description"] as? String) ?? (event.payload["name"] as? String) ?? ""
            let allowed = parseAllowed(from: event.payload["allowedDecisions"])
            enqueue(
                ApprovalRequest(
                    id: id,
                    kind: .plugin,
                    title: title,
                    detail: detail,
                    command: nil,
                    agentId: (event.payload["agentId"] as? String),
                    sessionKey: (event.payload["sessionKey"] as? String),
                    expiresAt: nil,
                    allowedDecisions: allowed
                )
            )
        default:
            break
        }
    }

    private func parseAllowed(from raw: Any?) -> Set<ApprovalRequest.Decision> {
        // Default policy: deny is always possible; otherwise trust the
        // backend's enumerated list when present.
        var set: Set<ApprovalRequest.Decision> = [.deny]
        if let arr = raw as? [String] {
            for token in arr {
                if let decision = ApprovalRequest.Decision(rawValue: token) {
                    set.insert(decision)
                }
            }
        } else if let arr = raw as? [Any] {
            for token in arr {
                if let s = token as? String, let decision = ApprovalRequest.Decision(rawValue: s) {
                    set.insert(decision)
                }
            }
        }
        if set.isEmpty { return [.deny] }
        return set
    }
}
