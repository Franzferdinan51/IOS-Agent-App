//
//  ApprovalInboxView.swift
//  DualAgent
//
//  Sheet UI for pending-approval requests. Mirrors Hermex's
//  `ApprovalRequestOverlay` / OpenClaw's `exec.approval.list`. Offers
//  Allow once / Allow session / Allow always / Deny depending on what
//  the backend allows.
//

import SwiftUI

struct ApprovalInboxView: View {
    @ObservedObject var coordinator: ApprovalInboxCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.pending.isEmpty {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.shield.fill",
                        description: Text("No pending approvals.")
                    )
                } else {
                    List {
                        ForEach(coordinator.pending) { request in
                            ApprovalRequestCard(request: request) { decision in
                                coordinator.resolve(request, decision: decision)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Approvals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if coordinator.pending.isEmpty { dismiss() }
                    }
                }
            }
        }
    }
}

struct ApprovalRequestCard: View {
    let request: ApprovalRequest
    let onDecision: (ApprovalRequest.Decision) -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: request.kind == .exec ? "terminal.fill" : "puzzlepiece.extension.fill")
                    .foregroundStyle(brand.primary)
                Text(request.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            if !request.detail.isEmpty {
                Text(request.detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let command = request.command {
                Text("$ \(command)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if request.allowedDecisions.contains(.allowOnce) {
                    decisionButton(.allowOnce, label: "Allow once", primary: false)
                }
                if request.allowedDecisions.contains(.allowSession) {
                    decisionButton(.allowSession, label: "Allow session", primary: false)
                }
                if request.allowedDecisions.contains(.allowAlways) {
                    decisionButton(.allowAlways, label: "Allow always", primary: false)
                }
                Spacer()
                if request.allowedDecisions.contains(.deny) {
                    decisionButton(.deny, label: "Deny", primary: true)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func decisionButton(_ decision: ApprovalRequest.Decision, label: String, primary: Bool) -> some View {
        Button {
            onDecision(decision)
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    primary ? Theme.error.opacity(0.15) : brand.primary.opacity(0.15),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(primary ? Theme.error : brand.primary, lineWidth: 1))
                .foregroundStyle(primary ? Theme.error : brand.primary)
        }
        .buttonStyle(.plain)
    }
}
