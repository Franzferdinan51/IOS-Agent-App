//
//  ConnectionStatePill.swift
//  DualAgent
//
//  Brand-colored status chip showing the connection state at the top of
//  the Sessions tab. Mirrors the Hermes "live / paused" pill and the
//  OpenClaw `connectionState` RPC event (we don't surface every RPC
//  detail here — just the user-visible status).
//

import SwiftUI

struct ConnectionStatePill: View {
    @ObservedObject var state: ConnectionState
    @Environment(\.brand) private var brand

    private var title: String {
        switch state.status {
        case .unknown: return "Checking connection…"
        case .connecting: return "Connecting…"
        case .ready: return "Connected"
        case .offline(let reason): return "Offline · \(reason)"
        }
    }

    private var symbol: String {
        switch state.status {
        case .unknown: return "questionmark.circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        case .offline: return "wifi.exclamationmark"
        }
    }

    private var tint: Color {
        switch state.status {
        case .ready: return brand.secondary
        case .connecting, .unknown: return brand.primary
        case .offline: return Theme.warning
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolEffect(.pulse, isActive: state.status == .connecting)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection: \(title)")
    }
}
